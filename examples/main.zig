const std = @import("std");
const zigi = @import("zigi");

const Context = struct {
    request_count: u32 = 0,
};

fn handleHello(stream: std.net.Stream, req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    _ = req;
    _ = stream;
    const ctx = @as(*Context, @ptrCast(@alignCast(context)));
    ctx.request_count += 1;
    var buf: [100]u8 = undefined;
    const json = try std.fmt.bufPrint(&buf, "{{\"message\":\"Hello from zigi!\",\"count\":{d}}}", .{ctx.request_count});
    try res.json(200, json);
}

fn handleInfo(stream: std.net.Stream, req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    _ = req;
    _ = context;
    _ = stream;
    try res.json(200, "{\"version\":\"0.1.0\",\"name\":\"zigi\"}");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = Context{};

    var server = try zigi.Server.init(allocator, 8080);
    defer server.deinit();

    std.log.info("zigi example server running on http://0.0.0.0:8080", .{});

    const routes = .{
        zigi.GET("/hello", handleHello),
        zigi.GET("/info", handleInfo),
    };

    try server.run(routes, &ctx);
}