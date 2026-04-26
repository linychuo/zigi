# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Codebase Overview

Zigi is a lightweight HTTP server library for Zig that provides compile-time route definitions, method-based routing, chunked transfer encoding support, and configurable CORS. It's built entirely using the Zig standard library with no external dependencies.

## Architecture

The codebase follows a modular architecture with clear separation of concerns:

- **`src/zigi.zig`** - Public API facade that re-exports all public types (entry point)
- **`src/server.zig`** - Core server implementation with connection handling and request parsing
- **`src/request.zig`** - HTTP request parsing, header management, and URL decoding
- **`src/response.zig`** - HTTP response building with various content types and status codes
- **`src/route.zig`** - Compile-time route definitions (GET, POST, etc.)
- **`src/util.zig`** - Utility functions for URL percent-decoding and chunked body parsing

## Key Design Patterns

1. **Compile-time Routing**: Routes are defined at compile time using Zig's comptime features, enabling zero-cost abstractions for route matching
2. **Thread-per-Connection**: Each connection spawns a new thread (with configurable limits for DoS protection)
3. **Zero-copy Parsing**: Headers and URLs are parsed without unnecessary copying where possible
4. **Memory Safety**: All allocations are tracked and properly freed in deinit methods

## Building and Development

### Build Commands
```bash
# Build the library module
zig build

# Build and run example (from examples/ directory)
cd examples && zig build

# Build with optimizations
zig build -Doptimize=ReleaseSafe

# Clean build cache
zig build clean
```

### Testing
The project currently lacks formal unit tests. To add tests:
```bash
# Create test file in src/ directory
# Run specific test file
zig test src/request.zig

# Run all tests
zig build test
```

### Development Workflow
1. Make changes to source files in `src/`
2. Run `zig build` to verify compilation
3. Create example programs to test functionality
4. Use Zig's built-in safety checks for memory safety verification

## API Usage Patterns

### Server Setup
```zig
const zigi = @import("zigi");

var server = try zigi.Server.init(allocator, 8080);
server.setMaxConnections(100);  // Configure connection limit
defer server.deinit();

const routes = .{
    zigi.GET("/hello", handleHello),
    zigi.POST("/api/data", handleData),
    zigi.GET("/user/:id", handleUser),  // Path parameters
};

try server.run(routes, &context);
```

### Handler Functions
```zig
fn handler(req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    // Access request data
    const method = req.method;
    const url = req.url;
    const content_length = req.content_length;
    
    // Parse headers (case-insensitive)
    if (req.getHeader("Content-Type")) |content_type| {
        // Handle content type
    }
    
    // Send responses
    try res.json(200, "{\"message\": \"Hello\"}");
    try res.html(200, "<h1>Hello World</h1>");
    try res.file(200, file_data, "document.pdf");
}
```

## Security Considerations

Recent fixes have addressed several critical security issues:
- Connection limiting to prevent DoS attacks
- Proper header parsing to prevent buffer overflows
- Input validation for HTTP methods and headers
- Memory safety fixes for URL decoding

Always verify that new changes maintain these security properties.

## Performance Characteristics

- **Compile-time route resolution** for zero-overhead routing
- **Minimal allocations** during request processing
- **Configurable connection limits** to prevent resource exhaustion
- **Efficient header parsing** with case-insensitive matching

## Important Implementation Notes

- **Handler signature**: `fn (req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) anyerror!void`
- **Context passing**: Context is passed from `server.run(routes, context)` to all handlers
- **Thread-safe shutdown**: Server uses `std.atomic.Value(bool)` for the running flag
- **HTTP parser compatibility**: Handles both `\r\n\r\n` and `\n\n` (LocalSend clients send non-standard CRLF)
- **Zig version requirement**: Requires Zig 0.15.2 (uses `ArrayList.initCapacity` and requires allocator passed to methods)

## Common Modification Patterns

1. **Adding new HTTP methods**: Extend the `Method` enum in `request.zig`
2. **Adding response types**: Add methods to `Response` struct in `response.zig`
3. **Enhancing routing**: Modify route matching logic in `route.zig`
4. **Adding utilities**: Place helper functions in `util.zig`

## Examples

```bash
cd examples && zig build run   # Run examples from project root
```

## Dependencies

None. The library uses only the Zig standard library, making it highly portable and dependency-free.
