# MJPEG Server

A flexible and efficient MJPEG streaming server written in Elixir. This server can receive JPEG frames over TCP and serve them as MJPEG streams over HTTP.

## Features

- Multiple independent MJPEG streams support
- Dynamic server management (start/stop streams at runtime)
- TCP frame ingestion
- HTTP MJPEG streaming
- Automatic port availability checking
- Keepalive support for maintaining connections
- CORS enabled for web integration

## Installation

Add `mjpeg_server` to your list of dependencies in `mix.exs`:

elixir
def deps do
  [
    {:mjpeg_server, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mjpeg_server>.

```
</```
rewritten_file>