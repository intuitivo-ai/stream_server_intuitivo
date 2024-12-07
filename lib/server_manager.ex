defmodule StreamServerIntuitivo.ServerManager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{servers: %{}}}
  end

  def start_server(name, tcp_host, tcp_port, http_port) do
    GenServer.call(__MODULE__, {:start_server, name, tcp_host, tcp_port, http_port}, 15_000)
  end

  def stop_server(name) do
    GenServer.call(__MODULE__, {:stop_server, name})
  end

  def get_server(name) do
    GenServer.call(__MODULE__, {:get_server, name})
  end

  def list_servers do
    GenServer.call(__MODULE__, :list_servers)
  end

  def handle_call({:start_server, name, tcp_host, tcp_port, http_port}, _from, state) do
    if Map.has_key?(state.servers, name) do
      {:reply, {:error, :already_exists}, state}
    else
      try do
        case StreamServerIntuitivo.start_server(name, tcp_host, tcp_port, http_port) do
          {:ok, pids} ->
            server_info = %{
              tcp_host: tcp_host,
              tcp_port: tcp_port,
              http_port: http_port,
              pids: pids,
              http_ref: pids.http_ref
            }
            new_state = put_in(state.servers[name], server_info)
            {:reply, {:ok, server_info}, new_state}
          {:error, :port_in_use} ->
            Logger.error("Port #{http_port} is already in use")
            {:reply, {:error, :port_in_use}, state}
          {:error, :tcp_connection_timeout} ->
            Logger.error("TCP connection timeout to #{tcp_host}:#{tcp_port}")
            {:reply, {:error, :tcp_connection_timeout}, state}
          {:error, {:tcp_connection_failed, reason}} ->
            Logger.error("TCP connection failed to #{tcp_host}:#{tcp_port}: #{inspect(reason)}")
            {:reply, {:error, :tcp_connection_failed}, state}
          error ->
            Logger.error("Failed to start server #{name}: #{inspect(error)}")
            {:reply, {:error, :start_failed}, state}
        end
      catch
        kind, error ->
          Logger.error("Unexpected error starting server: #{inspect(kind)} #{inspect(error)}")
          {:reply, {:error, :unexpected_error}, state}
      end
    end
  end

  def handle_call({:stop_server, name}, _from, state) do
    case Map.get(state.servers, name) do
      nil ->
        {:reply, {:error, :not_found}, state}
      server_info ->
        case StreamServerIntuitivo.stop_server(server_info.pids) do
          :ok ->
            new_state = %{state | servers: Map.delete(state.servers, name)}
            {:reply, :ok, new_state}
          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:get_server, name}, _from, state) do
    {:reply, Map.get(state.servers, name), state}
  end

  def handle_call(:list_servers, _from, state) do
    {:reply, state.servers, state}
  end
end
