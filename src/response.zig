const std = @import("std");
const net = std.net;

pub const Status = struct {
    pub const OK = 200;
    pub const CREATED = 201;
    pub const NO_CONTENT = 204;
    pub const BAD_REQUEST = 400;
    pub const UNAUTHORIZED = 401;
    pub const FORBIDDEN = 403;
    pub const NOT_FOUND = 404;
    pub const METHOD_NOT_ALLOWED = 405;
    pub const REQUEST_TIMEOUT = 408;
    pub const CLIENT_CLOSED_REQUEST = 499;
    pub const INTERNAL_SERVER_ERROR = 500;
    pub const NOT_IMPLEMENTED = 501;
    pub const SERVICE_UNAVAILABLE = 503;

    pub fn text(code: u16) []const u8 {
        return switch (code) {
            200 => "OK",
            201 => "Created",
            204 => "No Content",
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            408 => "Request Timeout",
            499 => "Client Closed Request",
            500 => "Internal Server Error",
            501 => "Not Implemented",
            503 => "Service Unavailable",
            else => "Unknown",
        };
    }
};

pub const ContentType = struct {
    pub const JSON = "application/json";
    pub const TEXT = "text/plain";
    pub const HTML = "text/html";
    pub const OCTET_STREAM = "application/octet-stream";

    pub fn fromExtension(ext: []const u8) []const u8 {
        if (std.mem.eql(u8, ext, "html") or std.mem.eql(u8, ext, "htm")) return HTML;
        if (std.mem.eql(u8, ext, "json")) return JSON;
        if (std.mem.eql(u8, ext, "txt") or std.mem.eql(u8, ext, "css") or std.mem.eql(u8, ext, "js")) return TEXT;
        if (std.mem.eql(u8, ext, "png")) return "image/png";
        if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) return "image/jpeg";
        if (std.mem.eql(u8, ext, "gif")) return "image/gif";
        if (std.mem.eql(u8, ext, "svg")) return "image/svg+xml";
        if (std.mem.eql(u8, ext, "ico")) return "image/x-icon";
        if (std.mem.eql(u8, ext, "pdf")) return "application/pdf";
        if (std.mem.eql(u8, ext, "zip")) return "application/zip";
        if (std.mem.eql(u8, ext, "gz") or std.mem.eql(u8, ext, "gzip")) return "application/gzip";
        return OCTET_STREAM;
    }
};

pub const Response = struct {
    stream: net.Stream,
    cors_origin: []const u8 = "*",

    pub fn init(stream: net.Stream) Response {
        return .{ .stream = stream };
    }

    pub fn withCors(self: Response, origin: []const u8) Response {
        return .{ .stream = self.stream, .cors_origin = origin };
    }

    pub fn json(self: Response, status_code: u16, body: []const u8) !void {
        return self.send(status_code, ContentType.JSON, body);
    }

    pub fn send(self: Response, status_code: u16, content_type: []const u8, body: []const u8) !void {
        // Calculate required buffer size dynamically
        const header_size = "HTTP/1.1  XXX  \r\nContent-Type: \r\nContent-Length: XXXXXXXXXX\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: \r\n\r\n".len +
                           Status.text(status_code).len + content_type.len + self.cors_origin.len + 20; // extra for numbers

        if (header_size <= 1024) {
            var header_buf: [1024]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{ status_code, Status.text(status_code), content_type, body.len, self.cors_origin },
            ) catch {
                try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nHeader Too Large");
                return;
            };
            try self.stream.writeAll(header);
        } else {
            // Use dynamic allocation for large headers
            const header_buf = try std.heap.page_allocator.alloc(u8, header_size);
            defer std.heap.page_allocator.free(header_buf);

            const header = std.fmt.bufPrint(
                header_buf,
                "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{ status_code, Status.text(status_code), content_type, body.len, self.cors_origin },
            ) catch {
                try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nHeader Too Large");
                return;
            };
            try self.stream.writeAll(header);
        }
        try self.stream.writeAll(body);
    }

    pub fn ok(self: Response) !void {
        const header_size = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: \r\n\r\n".len + self.cors_origin.len;

        if (header_size <= 256) {
            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        } else {
            const header_buf = try std.heap.page_allocator.alloc(u8, header_size);
            defer std.heap.page_allocator.free(header_buf);

            const header = std.fmt.bufPrint(
                header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        }
    }

    pub fn continue_(self: Response) !void {
        const header_size = "HTTP/1.1 100 Continue\r\nAccess-Control-Allow-Origin: \r\n\r\n".len + self.cors_origin.len;

        if (header_size <= 256) {
            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 100 Continue\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        } else {
            const header_buf = try std.heap.page_allocator.alloc(u8, header_size);
            defer std.heap.page_allocator.free(header_buf);

            const header = std.fmt.bufPrint(
                header_buf,
                "HTTP/1.1 100 Continue\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        }
    }

    pub fn sendError(self: Response, status_code: u16, message: []const u8) !void {
        try self.send(status_code, ContentType.TEXT, message);
    }

    pub fn okJson(self: Response, body: []const u8) !void {
        try self.json(Status.OK, body);
    }

    pub fn okEmpty(self: Response) !void {
        const header_size = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: \r\n\r\n".len + self.cors_origin.len;

        if (header_size <= 256) {
            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        } else {
            const header_buf = try std.heap.page_allocator.alloc(u8, header_size);
            defer std.heap.page_allocator.free(header_buf);

            const header = std.fmt.bufPrint(
                header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{self.cors_origin},
            ) catch {
                return;
            };
            try self.stream.writeAll(header);
        }
    }

    pub fn badRequest(self: Response, message: []const u8) !void {
        try self.json(Status.BAD_REQUEST, message);
    }

    pub fn forbidden(self: Response, message: []const u8) !void {
        try self.json(Status.FORBIDDEN, message);
    }

    pub fn notFound(self: Response, message: []const u8) !void {
        try self.json(Status.NOT_FOUND, message);
    }

    pub fn clientClosed(self: Response, message: []const u8) !void {
        try self.json(Status.CLIENT_CLOSED_REQUEST, message);
    }

    pub fn internalError(self: Response, message: []const u8) !void {
        try self.json(Status.INTERNAL_SERVER_ERROR, message);
    }

    pub fn methodNotAllowed(self: Response, message: []const u8) !void {
        try self.json(Status.METHOD_NOT_ALLOWED, message);
    }

    pub fn html(self: Response, status_code: u16, body: []const u8) !void {
        try self.send(status_code, ContentType.HTML, body);
    }

    pub fn file(self: Response, status_code: u16, body: []const u8, filename: []const u8) !void {
        const ext = if (std.mem.lastIndexOf(u8, filename, ".")) |i| filename[i + 1..] else "";
        const content_type = ContentType.fromExtension(ext);

        // Calculate required buffer size dynamically
        const header_size = "HTTP/1.1  XXX  \r\nContent-Type: \r\nContent-Length: XXXXXXXXXX\r\nContent-Disposition: attachment; filename=\"\"\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: \r\n\r\n".len +
                           Status.text(status_code).len + content_type.len + filename.len + self.cors_origin.len + 20;

        if (header_size <= 1024) {
            var header_buf: [1024]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nContent-Disposition: attachment; filename=\"{s}\"\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{ status_code, Status.text(status_code), content_type, body.len, filename, self.cors_origin },
            ) catch {
                try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
                return;
            };
            try self.stream.writeAll(header);
        } else {
            const header_buf = try std.heap.page_allocator.alloc(u8, header_size);
            defer std.heap.page_allocator.free(header_buf);

            const header = std.fmt.bufPrint(
                header_buf,
                "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nContent-Disposition: attachment; filename=\"{s}\"\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: {s}\r\n\r\n",
                .{ status_code, Status.text(status_code), content_type, body.len, filename, self.cors_origin },
            ) catch {
                try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
                return;
            };
            try self.stream.writeAll(header);
        }
        try self.stream.writeAll(body);
    }
};