# zigi

Lightweight HTTP server library for Zig.

## Features

- Compile-time route definitions
- Method + URL routing (exact and prefix matching)
- Streaming request/response support
- Chunked transfer encoding support
- Thread-safe server shutdown via atomic flags
- Handles non-standard CRLF (LocalSend clients)

## Usage

```zig
const zigi = @import("zigi");

fn handleHello(stream: std.net.Stream, req: *zigi.Request, context: ?*anyopaque) !void {
    _ = req;
    _ = context;
    const res = zigi.Response.init(stream);
    try res.json(200, "{\"message\":\"Hello!\"}");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var server = try zigi.Server.init(gpa.allocator(), 8080);
    defer server.deinit();

    const routes = .{
        zigi.GET("/hello", handleHello),
    };

    try server.run(routes, null);
}
```

## API

### Request

- `req.method` - HTTP method (GET, POST, etc.)
- `req.url` - URL path without query string
- `req.query` - Query string without `?`
- `req.headers` - Raw headers buffer
- `req.content_length` - Content-Length if present
- `req.stream` - Raw TCP stream for streaming uploads
- `req.getHeader(name)` - Get header value (case-insensitive)
- `req.getQueryParam(param)` - Extract query parameter

### Response

- `res.json(status, body)` - Send JSON response
- `res.send(status, content_type, body)` - Send raw response
- `res.ok()` / `res.okEmpty()` - Empty 200 OK
- `res.badRequest(msg)` / `res.notFound(msg)` / etc.

### Server

- `Server.init(allocator, port)` - Create server
- `Server.run(routes, context)` - Start listening
- `Server.deinit()` - Graceful shutdown

### Routes

- `zigi.GET(url, handler)` - GET route
- `zigi.POST(url, handler)` - POST route
- `zigi.routePrefix(method, prefix, handler)` - Prefix matching

## Dependencies

None. Pure Zig standard library.