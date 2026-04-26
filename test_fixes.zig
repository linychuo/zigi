const std = @import("std");
const zigi = @import("src/zigi.zig");

const Context = struct {
    request_count: u32 = 0,
};

fn handleHello(req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    _ = req;
    const ctx = @as(*Context, @ptrCast(@alignCast(context)));
    ctx.request_count += 1;
    var buf: [100]u8 = undefined;
    const json = try std.fmt.bufPrint(&buf, "{{\"message\":\"Hello from zigi!\",\"count\":{d}}}", .{ctx.request_count});
    try res.json(200, json);
}

fn handleInfo(req: *zigi.Request, res: *zigi.Response, context: ?*anyopaque) !void {
    _ = req;
    _ = context;
    try res.json(200, "{\"version\":\"0.1.0\",\"name\":\"zigi\"}");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = Context{};

    var server = try zigi.Server.init(allocator, 8080);
    defer server.deinit();

    // Test the new connection limiting feature
    server.setMaxConnections(50);

    std.log.info("zigi test server running on http://0.0.0.0:8080", .{});

    const routes = .{
        zigi.GET("/hello", handleHello),
        zigi.GET("/info", handleInfo),
    };

    try server.run(routes, &ctx);
}