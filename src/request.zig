const std = @import("std");
const net = std.net;

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    UNKNOWN,

    pub fn fromString(s: []const u8) Method {
        if (std.mem.eql(u8, s, "GET")) return .GET;
        if (std.mem.eql(u8, s, "POST")) return .POST;
        if (std.mem.eql(u8, s, "PUT")) return .PUT;
        if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
        return .UNKNOWN;
    }

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .UNKNOWN => "UNK",
        };
    }
};

pub const Request = struct {
    allocator: std.mem.Allocator,
    method: Method,
    url: []const u8,
    query: []const u8,
    headers: []u8,
    body_start_offset: usize,
    content_length: ?usize,
    chunked_transfer: bool,
    stream: ?net.Stream,

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.headers);
    }

    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        var line_it = std.mem.splitScalar(u8, self.headers, '\n');
        while (line_it.next()) |line| {
            const clean_line: []const u8 = if (std.mem.indexOfScalar(u8, line, '\r')) |r| line[0..r] else line;
            if (clean_line.len > name.len and std.ascii.eqlIgnoreCase(clean_line[0..name.len], name)) {
                var i = name.len;
                while (i < clean_line.len and clean_line[i] == ' ') i += 1;
                return clean_line[i..];
            }
        }
        return null;
    }

    pub fn getQueryParam(self: *const Request, param: []const u8) ?[]const u8 {
        if (self.query.len == 0) return null;
        const param_start = std.mem.indexOf(u8, self.query, param) orelse return null;
        const after_param = self.query[param_start + param.len..];
        if (after_param.len == 0 or after_param[0] != '=') return null;
        const value_start = after_param[1..];
        const value_end = std.mem.indexOfScalar(u8, value_start, '&') orelse value_start.len;
        return value_start[0..value_end];
    }

    pub fn body(self: *Request) ![]u8 {
        const content_len = self.content_length orelse return error.NoContentLength;

        const buffered_start = self.body_start_offset;
        const buffered_len = if (buffered_start < self.headers.len) self.headers.len - buffered_start else 0;

        if (buffered_len > 0) {
            if (buffered_len >= content_len) {
                var buf = try self.allocator.alloc(u8, content_len);
                @memcpy(buf[0..content_len], self.headers[buffered_start..][0..content_len]);
                return buf;
            }
            const stream = self.stream orelse return error.NoStream;

            var buf = try self.allocator.alloc(u8, content_len);
            @memcpy(buf[0..buffered_len], self.headers[buffered_start..]);
            var remaining = content_len - buffered_len;
            var offset = buffered_len;

            while (remaining > 0) {
                const n = stream.read(buf[offset..offset + remaining]) catch return error.ReadError;
                if (n == 0) return error.ConnectionClosed;
                offset += n;
                remaining -= n;
            }
            return buf;
        }

        const stream = self.stream orelse return error.NoStream;
        var buf = try self.allocator.alloc(u8, content_len);
        var remaining = content_len;
        var offset: usize = 0;

        while (remaining > 0) {
            const n = stream.read(buf[offset..offset + remaining]) catch return error.ReadError;
            if (n == 0) return error.ConnectionClosed;
            offset += n;
            remaining -= n;
        }
        return buf;
    }
};