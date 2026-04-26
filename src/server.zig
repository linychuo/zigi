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

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) !Self {
        const listen_addr = try net.Address.parseIp4("0.0.0.0", port);
        const listener = try listen_addr.listen(.{ .reuse_address = true });
        return Self{
            .allocator = allocator,
            .listener = listener,
        };
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .seq_cst);
        self.listener.deinit();
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
            };
        }
    }

    fn handleConnection(self: *Self, comptime routes: anytype, context: ?*anyopaque, conn: net.Server.Connection) void {
        var mutable_conn = conn;
        defer mutable_conn.stream.close();

        var req = parseRequest(self.allocator, &mutable_conn) catch return;
        defer req.deinit();

        var res = Response.init(mutable_conn.stream);

        inline for (routes, 0..) |route_item, _i| {
            _ = _i;
            if (route_item.matches(req.method, req.url)) {
                route_item.handler(mutable_conn.stream, &req, &res, context) catch |err| {
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
                if (std.mem.indexOf(u8, clean_line, "chunked") != null) {
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
        .stream = conn.stream,
    };
}

pub fn streamFile(
    stream: net.Stream,
    expected_size: usize,
    writer: anytype,
    progress_callback: ?fn (bytes_written: usize, total: usize) void,
) !usize {
    var total_written: usize = 0;
    var chunk_buf: [65536]u8 = undefined;

    while (total_written < expected_size) {
        const remaining = expected_size - total_written;
        const to_read = @min(chunk_buf.len, remaining);
        const n = stream.read(chunk_buf[0..to_read]) catch return error.ReadError;
        if (n == 0) break;
        try writer.writeAll(chunk_buf[0..n]);
        total_written += n;

        if (progress_callback) |cb| {
            cb(total_written, expected_size);
        }
    }

    return total_written;
}

pub fn streamFileChunked(
    stream: net.Stream,
    writer: anytype,
    max_size: usize,
) !usize {
    return try decodeChunkedTransfer(stream, writer, max_size);
}

pub fn decodeChunkedTransfer(
    stream: net.Stream,
    writer: anytype,
    max_size: usize,
) !usize {
    var total_written: usize = 0;
    var chunk_buf: [65536]u8 = undefined;

    while (true) {
        var size_buf: [32]u8 = undefined;
        var size_len: usize = 0;

        while (size_len < size_buf.len) {
            const n = try stream.read(size_buf[size_len..]);
            if (n == 0) break;
            size_len += n;
            if (size_len >= 2 and size_buf[size_len - 1] == '\n' and size_buf[size_len - 2] == '\r') {
                break;
            }
        }

        if (size_len < 3) break;

        const size_str = std.mem.trim(u8, size_buf[0..size_len - 2], " \t");
        const chunk_size = std.fmt.parseUnsigned(usize, size_str, 16) catch 0;

        if (chunk_size == 0) break;

        if (total_written + chunk_size > max_size) {
            return error.FileTooLarge;
        }

        var remaining = chunk_size;
        while (remaining > 0) {
            const to_read = @min(chunk_buf.len, remaining);
            const n = try stream.read(chunk_buf[0..to_read]);
            if (n == 0) break;
            try writer.writeAll(chunk_buf[0..n]);
            total_written += n;
            remaining -= n;
        }

        var crlf: [2]u8 = undefined;
        _ = try stream.read(&crlf);
    }

    return total_written;
}