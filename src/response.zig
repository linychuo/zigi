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
};

pub const ContentType = struct {
    pub const JSON = "application/json";
    pub const TEXT = "text/plain";
    pub const HTML = "text/html";
    pub const OCTET_STREAM = "application/octet-stream";
};

pub const Response = struct {
    stream: net.Stream,

    pub fn init(stream: net.Stream) Response {
        return .{ .stream = stream };
    }

    pub fn json(self: Response, status_code: u16, body: []const u8) !void {
        return self.send(status_code, ContentType.JSON, body);
    }

    pub fn send(self: Response, status_code: u16, content_type: []const u8, body: []const u8) !void {
        var header_buf: [1024]u8 = undefined;
        const header = std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
            .{ status_code, content_type, body.len },
        ) catch {
            try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nHeader Too Large");
            return;
        };
        try self.stream.writeAll(header);
        try self.stream.writeAll(body);
    }

    pub fn ok(self: Response) !void {
        try self.stream.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n");
    }

    pub fn continue_(self: Response) !void {
        try self.stream.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
    }

    pub fn sendError(self: Response, status_code: u16, message: []const u8) !void {
        try self.send(status_code, ContentType.TEXT, message);
    }

    pub fn okJson(self: Response, body: []const u8) !void {
        try self.json(Status.OK, body);
    }

    pub fn okEmpty(self: Response) !void {
        try self.stream.writeAll("HTTP/1.1 200 OK\r\n");
        try self.stream.writeAll("Content-Length: 0\r\n");
        try self.stream.writeAll("Connection: keep-alive\r\n");
        try self.stream.writeAll("Access-Control-Allow-Origin: *\r\n");
        try self.stream.writeAll("\r\n");
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

    pub fn html(self: Response, status_code: u16, body: []const u8) !void {
        try self.send(status_code, ContentType.HTML, body);
    }

    pub fn file(self: Response, status_code: u16, body: []const u8, filename: []const u8) !void {
        var header_buf: [1024]u8 = undefined;
        const header = std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nContent-Disposition: attachment; filename=\"{s}\"\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
            .{ status_code, ContentType.OCTET_STREAM, body.len, filename },
        ) catch {
            try self.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
            return;
        };
        try self.stream.writeAll(header);
        try self.stream.writeAll(body);
    }
};