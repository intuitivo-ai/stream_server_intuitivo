defmodule MjpegServer do
  use Application
  require Logger

  def start(_type, _args) do
    # Cleanup any leftover Cowboy listeners
    cleanup_cowboy_listeners()

    children = [
      {Registry, keys: :duplicate, name: MjpegServer.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: MjpegServer.DynamicSupervisor},
      {MjpegServer.ServerManager, []}
    ]

    opts = [strategy: :one_for_one, name: MjpegServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    cleanup_cowboy_listeners()
    :ok
  end

  defp cleanup_cowboy_listeners do
    # Get all running Ranch listeners
    case :ranch.info() do
      [] ->
        :ok
      listeners ->
        # Stop each listener
        Enum.each(listeners, fn {ref, _} ->
          :ranch.stop_listener(ref)
        end)
        # Give it a moment to fully cleanup
        Process.sleep(100)
    end
  end

  def start_server(name, tcp_host, tcp_port, http_port) do
    # Check if HTTP port is available
    case check_port_available(http_port) do
      true ->
        http_ref = String.to_atom("#{name}_http")

        case DynamicSupervisor.start_child(
          MjpegServer.DynamicSupervisor,
          {Plug.Cowboy,
            scheme: :http,
            plug: {MjpegServer.Router, server_name: name},
            options: [
              port: http_port,
              ip: {0,0,0,0},
              ref: http_ref
            ]
          }
        ) do
          {:ok, http_pid} ->
            try do
              tcp_start_result = Task.await(
                Task.async(fn ->
                  DynamicSupervisor.start_child(
                    MjpegServer.DynamicSupervisor,
                    {MjpegServer.TcpClient, {name, tcp_host, tcp_port}}
                  )
                end),
                8_000  # Reduced to 8 seconds to ensure it's less than GenServer timeout
              )

              case tcp_start_result do
                {:ok, tcp_pid} ->
                  {:ok, %{http_pid: http_pid, tcp_pid: tcp_pid, http_ref: http_ref}}
                {:error, reason} ->
                  cleanup_http_server(http_pid, http_ref)
                  {:error, {:tcp_connection_failed, reason}}
              end
            catch
              :exit, {:timeout, _} ->
                cleanup_http_server(http_pid, http_ref)
                {:error, :tcp_connection_timeout}
            end
          error ->
            error
        end
      false ->
        {:error, :port_in_use}
    end
  end

  defp check_port_available(port) do
    case :gen_tcp.listen(port, [:binary, ip: {0,0,0,0}]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true
      {:error, :eaddrinuse} ->
        false
    end
  end

  def stop_server(%{http_pid: http_pid, tcp_pid: tcp_pid, http_ref: http_ref}) do
    # Stop both services, continue even if one fails
    http_result = DynamicSupervisor.terminate_child(MjpegServer.DynamicSupervisor, http_pid)
    tcp_result = DynamicSupervisor.terminate_child(MjpegServer.DynamicSupervisor, tcp_pid)

    # Also stop the Ranch listener explicitly
    :ranch.stop_listener(http_ref)

    case {http_result, tcp_result} do
      {:ok, :ok} -> :ok
      error -> {:error, error}
    end
  end

  # Add helper function to cleanup HTTP server
  defp cleanup_http_server(http_pid, http_ref) do
    DynamicSupervisor.terminate_child(MjpegServer.DynamicSupervisor, http_pid)
    :ranch.stop_listener(http_ref)
  end
end

defmodule MjpegServer.Router do
  use Plug.Router
  require Logger

  plug :match
  plug :dispatch

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    conn = assign(conn, :server_name, opts[:server_name])
    super(conn, opts)
  end

  get "/" do
    server_name = conn.assigns.server_name
    frames_key = "#{server_name}_frames"

    conn = put_resp_header(conn, "content-type", "multipart/x-mixed-replace; boundary=frame")
    conn = put_resp_header(conn, "access-control-allow-origin", "*")
    conn = put_resp_header(conn, "cache-control", "no-cache, private")
    conn = put_resp_header(conn, "pragma", "no-cache")

    # Register this process to receive frames for this specific server
    {:ok, _} = Registry.register(MjpegServer.Registry, frames_key, {})

    conn = send_chunked(conn, 200)

    try do
      stream_frames(conn)
    after
      Registry.unregister(MjpegServer.Registry, frames_key)
    end
  end

  defp stream_frames(conn) do
    receive do
      {:jpeg_frame, frame_data} ->
        case chunk(conn, build_frame(frame_data)) do
          {:ok, conn} ->
            stream_frames(conn)
          {:error, :closed} ->
            Logger.info("Client disconnected")
            conn
        end
    after
      5_000 -> # Reduced timeout and added keepalive
        case chunk(conn, build_keepalive()) do
          {:ok, conn} ->
            stream_frames(conn)
          {:error, :closed} ->
            Logger.info("Client disconnected during keepalive")
            conn
        end
    end
  end

  defp build_frame(jpeg_data) do
    [
      "--frame\r\n",
      "Content-Type: image/jpeg\r\n",
      "Content-Length: #{byte_size(jpeg_data)}\r\n\r\n",
      jpeg_data,
      "\r\n"
    ]
  end

  # Add keepalive frame
  defp build_keepalive do
    [
      "--frame\r\n",
      "Content-Type: text/plain\r\n",
      "Content-Length: 9\r\n\r\n",
      "keepalive\r\n",
      "\r\n"
    ]
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end

defmodule MjpegServer.TcpClient do
  use GenServer
  require Logger

  def start_link({server_name, host, port}) do
    GenServer.start_link(__MODULE__, {server_name, host, port})
  end

  @impl true
  def init({server_name, host, port}) do
    case :gen_tcp.connect(String.to_charlist(host), port,
      [:binary, active: true], 5_000) do
      {:ok, socket} ->
        {:ok, %{socket: socket, buffer: <<>>, server_name: server_name}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:tcp, _socket, data}, %{buffer: buffer} = state) do
    new_buffer = buffer <> data

    try do
      {frames, remaining_buffer} = extract_frames(new_buffer)

      Enum.each(frames, fn frame ->
        Process.send_after(self(), {:broadcast_frame, frame}, 0)
      end)

      {:noreply, %{state | buffer: remaining_buffer}}
    rescue
      e ->
        Logger.error("Error processing TCP data: #{inspect(e)}")
        {:noreply, %{state | buffer: ""}}
    end
  end

  @impl true
  def handle_info({:broadcast_frame, frame}, %{server_name: server_name} = state) do
    frames_key = "#{server_name}_frames"
    Registry.dispatch(MjpegServer.Registry, frames_key, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:jpeg_frame, frame})
    end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warn("TCP connection closed")
    {:stop, :normal, state}
  end

  defp extract_frames(buffer) do
    extract_frames(buffer, [])
  end

  defp extract_frames(buffer, frames) do
    case find_jpeg_frame(buffer) do
      {:ok, frame, rest} ->
        extract_frames(rest, [frame | frames])
      :incomplete ->
        {Enum.reverse(frames), buffer}
    end
  end

  defp find_jpeg_frame(buffer) do
    case :binary.match(buffer, <<0xFF, 0xD8>>) do
      {start_pos, _} ->
        remaining = binary_part(buffer, start_pos, byte_size(buffer) - start_pos)
        case :binary.match(remaining, <<0xFF, 0xD9>>) do
          {end_pos, _} ->
            frame_end = end_pos + 2
            frame = binary_part(remaining, 0, frame_end)
            rest = binary_part(buffer, start_pos + frame_end, byte_size(buffer) - (start_pos + frame_end))
            {:ok, frame, rest}
          :nomatch ->
            :incomplete
        end
      :nomatch ->
        :incomplete
    end
  end
end
