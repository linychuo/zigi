# zigi

Lightweight HTTP server library for Zig.

## Features

- Compile-time route definitions with path parameters (e.g., `/user/:id`)
- Method + URL routing (exact, prefix, and param matching)
- Chunked transfer encoding support
- URL percent-decoding
- Configurable CORS
- Thread-safe server shutdown via atomic flags
- Handles non-standard CRLF (LocalSend clients)

## Usage

```zig
const zigi = @import("zigi");

const Context = struct {
    request_count: u32 = 0,
};

fn handleHello(req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    const ctx = @as(*Context, @ptrCast(@alignCast(context)));
    ctx.request_count += 1;
    try res.json(200, "Hello!");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var ctx = Context{};
    var server = try zigi.Server.init(gpa.allocator(), 8080);
    defer server.deinit();

    const routes = .{
        zigi.GET("/hello", handleHello),
        zigi.GET("/user/:id", handleUser),
    };

    try server.run(routes, &ctx);
}
```

## API

### Request

- `req.method` - HTTP method (GET, POST, etc.)
- `req.url` - URL path without query string
- `req.query` - Query string without `?`
- `req.headers` - Raw headers buffer
- `req.content_length` - Content-Length if present
- `req.chunked_transfer` - True if Transfer-Encoding: chunked
- `req.getHeader(name)` - Get header value (case-insensitive)
- `req.getQueryParam(param)` - Extract query parameter value
- `req.body(stream, max_size)` - Read request body (supports chunked)
- `req.decodeUrl()` - Decode percent-encoded URL

### Response

- `res.json(status, body)` - Send JSON response
- `res.send(status, content_type, body)` - Send raw response
- `res.ok()` / `res.okEmpty()` - Empty 200 OK
- `res.badRequest(msg)` / `res.notFound(msg)` / etc.
- `res.html(status, body)` - Send HTML response
- `res.file(status, body, filename)` - Send file with auto content-type
- `res.withCors(origin)` - Create response with custom CORS origin

### Server

- `Server.init(allocator, port)` - Create server
- `Server.run(routes, context)` - Start listening (blocks)
- `Server.setConnectionTimeout(seconds)` - Set parse timeout
- `Server.deinit()` - Graceful shutdown

### Routes

- `zigi.GET(url, handler)` / `zigi.POST(url, handler)` / etc.
- `zigi.route(method, url, handler)` - Exact URL match
- `zigi.routePrefix(method, prefix, handler)` - Prefix matching
- Path parameters: `zigi.GET("/user/:id", handler)` captures `123` from `/user/123`

### Handler Signature

```zig
fn handler(req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) anyerror!void
```

## Installation

Add `zigi` as a dependency in your `build.zig.zon`:

```bash
zig fetch --save git@github.com:linychuo/zigi.git
```

Or manually add to your `build.zig.zon`:

```zon
.dependencies = .{
    .zigi = .{
        .url = "git@github.com:linychuo/zigi.git",
        .hash = "<run zig fetch to get hash>",
    },
},
```

Then add to your `build.zig`:

```zig
const zigi_mod = b.dependency("zigi", .{}).module("zigi");
exe.root_module.addImport("zigi", zigi_mod);
```

## Dependencies

None. Pure Zig standard library.

## Project Structure

```
src/
├── zigi.zig      # Public API facade
├── request.zig   # Request parsing and Method enum
├── response.zig  # Response building and Status/ContentType
├── route.zig     # Route definitions and handlers
├── server.zig    # Server implementation
└── util.zig      # URL decoding and chunked body parsing
```