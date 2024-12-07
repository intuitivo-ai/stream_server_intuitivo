# MjpegServer

A lightweight Elixir MJPEG streaming server that can handle multiple camera streams simultaneously. It accepts MJPEG streams over TCP and makes them available via HTTP.

## Features

- Multiple concurrent MJPEG stream support
- Dynamic server management (start/stop streams)
- HTTP streaming with multipart/x-mixed-replace
- Automatic connection recovery
- CORS support
- Keepalive mechanism
- Clean shutdown handling

## Installation

Add `mjpeg_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mjpeg_server, "~> 0.1.0"}
  ]
end
```

## Usage

### Starting a Stream Server

```elixir
# Start a new MJPEG server
MjpegServer.ServerManager.start_server(
  "camera1",           # Unique name for this stream
  "192.168.1.100",    # TCP host (camera IP)
  6001,               # TCP port
  8081                # HTTP port where the stream will be available
)
```

### Managing Servers

```elixir
# List all running servers
MjpegServer.ServerManager.list_servers()

# Get information about a specific server
MjpegServer.ServerManager.get_server("camera1")

# Stop a server
MjpegServer.ServerManager.stop_server("camera1")
```

### Error Handling

The server will return various error tuples depending on the situation:

```elixir
{:error, :already_exists}         # When trying to start a server with an existing name
{:error, :port_in_use}           # When the HTTP port is already in use
{:error, :tcp_connection_timeout} # When TCP connection times out
{:error, :tcp_connection_failed}  # When TCP connection fails for other reasons
{:error, :not_found}             # When trying to stop a non-existent server
```

### Timeouts

The server implements several timeout levels:
- TCP Connection: 5 seconds
- Server Start Operation: 8 seconds
- GenServer Call: 15 seconds
- HTTP Stream Keepalive: 5 seconds

### HTTP Stream Access

Once a server is started, the MJPEG stream can be accessed at:
```
http://localhost:<http_port>/
```

The stream uses `multipart/x-mixed-replace` with CORS enabled and includes keepalive frames to maintain connection.

## Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Start an interactive shell
iex -S mix
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mjpeg_server>.

