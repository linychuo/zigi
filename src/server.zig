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
    max_concurrent_connections: u16 = 100, // Default limit
    current_connections: std.atomic.Value(u16) = std.atomic.Value(u16).init(0),

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

    pub fn setMaxConnections(self: *Self, max_connections: u16) void {
        self.max_concurrent_connections = max_connections;
    }

    pub fn run(self: *Self, comptime routes: anytype, context: ?*anyopaque) !void {
        self.running.store(true, .seq_cst);
        std.log.info("HTTP server listening on 0.0.0.0:{d}", .{self.listener.listen_address.getPort()});

        while (self.running.load(.seq_cst)) {
            const conn = self.listener.accept() catch |err| {
                std.log.warn("Accept error: {}", .{err});
                continue;
            };

            // Check connection limit
            const current_conn_count = self.current_connections.load(.seq_cst);
            if (current_conn_count >= self.max_concurrent_connections) {
                std.log.warn("Connection limit reached ({d}), rejecting connection", .{self.max_concurrent_connections});
                conn.stream.close();
                continue;
            }

            // Increment connection counter
            _ = self.current_connections.fetchAdd(1, .seq_cst);

            _ = std.Thread.spawn(.{}, Self.handleConnection, .{
                self,
                routes,
                context,
                conn,
            }) catch |err| {
                std.log.warn("Failed to spawn connection thread: {}", .{err});
                conn.stream.close();
                _ = self.current_connections.fetchSub(1, .seq_cst);
                continue;
            };
        }
    }

    fn handleConnection(self: *Self, comptime routes: anytype, context: ?*anyopaque, conn: net.Server.Connection) void {
        defer {
            // Decrement connection counter when done
            _ = self.current_connections.fetchSub(1, .seq_cst);
        }

        const start_time = std.time.nanoTimestamp();
        var mutable_conn = conn;
        defer mutable_conn.stream.close();

        var req = parseRequest(self.allocator, &mutable_conn) catch {
            std.log.warn("Failed to parse request", .{});
            return;
        };
        defer req.deinit();

        const parse_time = std.time.nanoTimestamp() - start_time;
        if (parse_time > self.connection_timeout_ns) {
            std.log.warn("Request parse timeout", .{});
            return;
        }

        // Validate HTTP method
        if (req.method == .UNKNOWN) {
            var res = Response.init(mutable_conn.stream);
            res.sendError(400, "Invalid HTTP Method") catch |write_err| {
                std.log.warn("Failed to send invalid method response: {}", .{write_err});
            };
            return;
        }

        req.decodeUrl();

        var res = Response.init(mutable_conn.stream);

        inline for (routes, 0..) |route_item, _i| {
            _ = _i;
            if (route_item.matches(req.method, req.url)) {
                route_item.handler(&req, &res, context) catch |err| {
                    std.log.warn("Handler error: {}", .{err});
                    res.internalError("Internal Server Error") catch |write_err| {
                        std.log.warn("Failed to send error response: {}", .{write_err});
                    };
                };
                return;
            }
        }

        res.notFound("Not Found") catch |write_err| {
            std.log.warn("Failed to send 404 response: {}", .{write_err});
        };
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

    // Find the actual end of headers to avoid including body data
    const sep_crlf = std.mem.indexOf(u8, header_buf[0..header_len], "\r\n\r\n");
    const sep_lf = std.mem.indexOf(u8, header_buf[0..header_len], "\n\n");
    const header_end = if (sep_crlf) |pos| pos + 4 else if (sep_lf) |pos| pos + 2 else header_len;

    const headers = try allocator.dupe(u8, header_buf[0..header_end]);

    const first_line_end = std.mem.indexOfScalar(u8, headers, '\r') orelse
        std.mem.indexOfScalar(u8, headers, '\n') orelse return error.InvalidRequest;
    const first_line = headers[0..first_line_end];

    var it = std.mem.splitScalar(u8, first_line, ' ');
    const method_str = it.next() orelse return error.InvalidRequest;
    const full_url = it.next() orelse "/";

    const query_start = std.mem.indexOfScalar(u8, full_url, '?');
    const url = if (query_start) |q| full_url[0..q] else full_url;
    const query = if (query_start) |q| full_url[q + 1..] else "";

    const body_start_offset: usize = header_end;
    var content_length: ?usize = null;
    var chunked_transfer = false;

    // Create a temporary request to use getHeader method for robust header parsing
    var temp_req = Request{
        .allocator = allocator,
        .method = Method.UNKNOWN,
        .url = "",
        .query = "",
        .headers = headers,
        .body_start_offset = body_start_offset,
        .content_length = null,
        .chunked_transfer = false,
        ._decoded_url = null,
        ._decoded_query = null,
    };

    // Parse Content-Length header with validation
    if (temp_req.getHeader("Content-Length")) |value| {
        if (value.len > 20) { // Prevent unreasonably large content-length values
            return error.InvalidRequest;
        }
        content_length = std.fmt.parseUnsigned(usize, value, 10) catch {
            return error.InvalidRequest;
        };
    }

    // Parse Transfer-Encoding header
    if (temp_req.getHeader("Transfer-Encoding")) |value| {
        if (std.mem.eql(u8, value, "chunked")) {
            chunked_transfer = true;
        }
        // For simplicity, only support chunked encoding
        else if (!std.mem.eql(u8, value, "identity")) {
            return error.InvalidRequest;
        }
    }

    // Validate that we don't have both Content-Length and Transfer-Encoding: chunked
    if (content_length != null and chunked_transfer) {
        return error.InvalidRequest;
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