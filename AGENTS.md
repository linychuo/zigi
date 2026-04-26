# zigi - Agent Instructions

## Build

```bash
zig build                    # Build library module
cd examples && zig build     # Build and run example
```

## Library Usage

Import: `const zigi = @import("zigi");`

Entry point: `src/zigi.zig` (re-exports all modules)

## Structure

- `src/zigi.zig` - Main module, re-exports everything
- `src/request.zig` - Request parsing
- `src/response.zig` - Response helpers
- `src/route.zig` - Route definitions (GET, POST, etc.)
- `src/server.zig` - Server implementation

## Important Notes

- Handler signature: `fn (req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) anyerror!void`
- `context` is passed from `server.run(routes, context)`
- Server `running` flag uses `std.atomic.Value(bool)` for thread-safe shutdown
- HTTP parser handles both `\r\n\r\n` and `\n\n` (LocalSend clients send non-standard)
- Requires Zig 0.15.2 (uses `ArrayList.initCapacity` and requires allocator passed to methods)

## Examples

```bash
zig build run   # in examples/ directory
```