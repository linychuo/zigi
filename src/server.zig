const std = @import("std");
const net = std.net;
const route = @import("route.zig");
const request = @import("request.zig");
const Method = request.Method;
const Request = request.Request;
const response = @import("response.zig");
const Response = response.Response;
const Handler = route.Handler;

pub const Server = struct {
    allocator: std.mem.Allocator,
    listener: net.Server,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    connection_timeout_ns: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) !Self {
        const listen_addr = try net.Address.parseIp4("0.0.0.0", port);
        const listener = try listen_addr.listen(.{ .reuse_address = true });
        return Self{
            .allocator = allocator,
            .listener = listener,
            .connection_timeout_ns = 30 * std.time.ns_per_s,
        };
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .seq_cst);
        self.listener.deinit();
    }

    pub fn setConnectionTimeout(self: *Self, seconds: u64) void {
        self.connection_timeout_ns = seconds * std.time.ns_per_s;
    }

    pub fn run(self: *Self, comptime routes: anytype, context: ?*anyopaque) !void {
        self.running.store(true, .seq_cst);
        std.log.info("HTTP server listening on 0.0.0.0:{d}", .{self.listener.listen_address.getPort()});

        while (self.running.load(.seq_cst)) {
            const conn = self.listener.accept() catch |err| {
                std.log.warn("Accept error: {}", .{err});
                continue;
            };
            _ = std.Thread.spawn(.{}, Self.handleConnection, .{
                self,
                routes,
                context,
                conn,
            }) catch |err| {
                std.log.warn("Failed to spawn connection thread: {}", .{err});
                conn.stream.close();
                continue;
            };
        }
    }

    fn handleConnection(self: *Self, comptime routes: anytype, context: ?*anyopaque, conn: net.Server.Connection) void {
        const start_time = std.time.nanoTimestamp();
        var mutable_conn = conn;
        defer mutable_conn.stream.close();

        var req = parseRequest(self.allocator, &mutable_conn) catch return;
        defer req.deinit();

        const parse_time = std.time.nanoTimestamp() - start_time;
        if (parse_time > self.connection_timeout_ns) {
            std.log.warn("Request parse timeout", .{});
            return;
        }

        req.decodeUrl();

        var res = Response.init(mutable_conn.stream);

        inline for (routes, 0..) |route_item, _i| {
            _ = _i;
            if (route_item.matches(req.method, req.url)) {
                route_item.handler(&req, &res, context) catch |err| {
                    std.log.warn("Handler error: {}", .{err});
                    res.sendError(500, "Internal Server Error") catch {};
                };
                return;
            }
        }

        res.sendError(404, "Not Found") catch {};
    }
};

pub fn parseRequest(allocator: std.mem.Allocator, conn: *net.Server.Connection) !Request {
    var header_buf: [8192]u8 = undefined;
    var header_len: usize = 0;

    while (header_len < header_buf.len) {
        const n = conn.stream.read(header_buf[header_len..]) catch return error.ReadError;
        if (n == 0) {
            if (header_len > 0) break;
            return error.ConnectionClosed;
        }
        header_len += n;

        if (std.mem.indexOf(u8, header_buf[0..header_len], "\r\n\r\n")) |_| break;
        if (std.mem.indexOf(u8, header_buf[0..header_len], "\n\n")) |_| break;
    }

    if (header_len == 0) return error.ConnectionClosed;

    const headers = try allocator.dupe(u8, header_buf[0..header_len]);

    const first_line_end = std.mem.indexOfScalar(u8, headers, '\r') orelse
        std.mem.indexOfScalar(u8, headers, '\n') orelse return error.InvalidRequest;
    const first_line = headers[0..first_line_end];

    var it = std.mem.splitScalar(u8, first_line, ' ');
    const method_str = it.next() orelse return error.InvalidRequest;
    const full_url = it.next() orelse "/";

    const query_start = std.mem.indexOfScalar(u8, full_url, '?');
    const url = if (query_start) |q| full_url[0..q] else full_url;
    const query = if (query_start) |q| full_url[q + 1..] else "";

    var body_start_offset: usize = header_len;
    var content_length: ?usize = null;
    var chunked_transfer = false;

    const sep_crlf = std.mem.indexOf(u8, headers, "\r\n\r\n");
    const sep_lf = std.mem.indexOf(u8, headers, "\n\n");
    const separator_pos = sep_crlf orelse sep_lf;
    if (separator_pos) |pos| {
        const sep_len = if (sep_crlf != null) @as(usize, 4) else @as(usize, 2);
        body_start_offset = pos + sep_len;
        const header_text = headers[0..pos];

        var line_it = std.mem.splitScalar(u8, header_text, '\n');
        while (line_it.next()) |line| {
            const clean_line: []const u8 = if (std.mem.indexOfScalar(u8, line, '\r')) |r| line[0..r] else line;

            if (std.mem.startsWith(u8, clean_line, "Content-Length:")) {
                const value = std.mem.trim(u8, clean_line[15..], " ");
                content_length = std.fmt.parseUnsigned(usize, value, 10) catch null;
            }
            if (std.mem.startsWith(u8, clean_line, "Transfer-Encoding:")) {
                const value = std.mem.trim(u8, clean_line[17..], " ");
                if (std.mem.eql(u8, value, "chunked")) {
                    chunked_transfer = true;
                }
            }
        }
    }

    return Request{
        .allocator = allocator,
        .method = Method.fromString(method_str),
        .url = url,
        .query = query,
        .headers = headers,
        .body_start_offset = body_start_offset,
        .content_length = content_length,
        .chunked_transfer = chunked_transfer,
    };
}