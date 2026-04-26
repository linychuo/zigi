const std = @import("std");
const net = std.net;
const util = @import("util.zig");

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
        // Validate input length to prevent buffer overruns
        if (s.len == 0 or s.len > 16) return .UNKNOWN;

        // Check for valid characters (letters only)
        for (s) |char| {
            if (!std.ascii.isAlphabetic(char)) return .UNKNOWN;
        }

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
    // Track decoded URL/query allocations for proper cleanup
    _decoded_url: ?[]u8 = null,
    _decoded_query: ?[]u8 = null,

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.headers);
        if (self._decoded_url) |decoded| {
            self.allocator.free(decoded);
        }
        if (self._decoded_query) |decoded| {
            self.allocator.free(decoded);
        }
    }

    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        var line_it = std.mem.splitScalar(u8, self.headers, '\n');
        while (line_it.next()) |line| {
            const clean_line: []const u8 = if (std.mem.indexOfScalar(u8, line, '\r')) |r| line[0..r] else line;

            // Find colon and check if header name matches (case-insensitive)
            if (std.mem.indexOfScalar(u8, clean_line, ':')) |colon_pos| {
                const header_name = std.mem.trim(u8, clean_line[0..colon_pos], " \t");
                if (std.ascii.eqlIgnoreCase(header_name, name)) {
                    const value_start = colon_pos + 1;
                    const header_value = std.mem.trim(u8, clean_line[value_start..], " \t");
                    return header_value;
                }
            }
        }
        return null;
    }

    pub fn getQueryParam(self: *const Request, param: []const u8) ?[]const u8 {
        if (self.query.len == 0) return null;
        var it = std.mem.splitScalar(u8, self.query, '&');
        while (it.next()) |pair| {
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                if (std.mem.eql(u8, pair[0..eq], param)) {
                    return pair[eq + 1..];
                }
            }
        }
        return null;
    }

    pub fn body(self: *Request, stream: net.Stream, max_size: usize) ![]u8 {
        if (self.chunked_transfer) {
            return util.decodeChunkedBody(stream, self.allocator, max_size);
        }
        const content_len = self.content_length orelse return error.NoContentLength;
        if (content_len > max_size) return error.BodyTooLarge;

        const buffered_start = self.body_start_offset;
        const buffered_len = if (buffered_start < self.headers.len) self.headers.len - buffered_start else 0;

        if (buffered_len > 0) {
            if (buffered_len >= content_len) {
                var buf = try self.allocator.alloc(u8, content_len);
                @memcpy(buf[0..content_len], self.headers[buffered_start..][0..content_len]);
                return buf;
            }
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

    pub fn decodeUrl(self: *Request) void {
        if (util.decodePercent(self.url, self.allocator)) |decoded| {
            self._decoded_url = decoded;
            self.url = decoded;
        }
        if (util.decodePercent(self.query, self.allocator)) |decoded| {
            self._decoded_query = decoded;
            self.query = decoded;
        }
    }
};