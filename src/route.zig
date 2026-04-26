const std = @import("std");
const Method = @import("request.zig").Method;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;

pub const Handler = fn (request: *Request, response: *Response, context: ?*anyopaque) anyerror!void;

pub const MatchFn = *const fn (method: Method, url: []const u8) bool;

pub fn Route(comptime HandlerType: type) type {
    return struct {
        handler: HandlerType,
        matchFn: MatchFn,

        pub fn matches(self: *const @This(), method: Method, url: []const u8) bool {
            return self.matchFn(method, url);
        }
    };
}

pub fn route(comptime m: Method, comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    const has_param = comptime std.mem.indexOf(u8, url, ":") != null;
    return .{
        .handler = handler,
        .matchFn = if (has_param) buildParamMatcher(m, url) else buildExactMatcher(m, url),
    };
}

fn buildExactMatcher(comptime method: Method, comptime url: []const u8) MatchFn {
    return struct {
        fn f(m: Method, u: []const u8) bool {
            return m == method and std.mem.eql(u8, u, url);
        }
    }.f;
}

fn buildParamMatcher(comptime method: Method, comptime pattern: []const u8) MatchFn {
    return struct {
        fn f(m: Method, u: []const u8) bool {
            if (m != method) return false;
            var pi: usize = 0;
            var ui: usize = 0;
            while (pi < pattern.len and ui < u.len) {
                if (pattern[pi] == ':') {
                    pi += 1;
                    while (pi < pattern.len and pattern[pi] != '/') pi += 1;
                    while (ui < u.len and u[ui] != '/') ui += 1;
                } else if (pattern[pi] == u[ui]) {
                    pi += 1;
                    ui += 1;
                } else {
                    return false;
                }
            }
            return pi == pattern.len and ui == u.len;
        }
    }.f;
}

pub fn routePrefix(comptime m: Method, comptime prefix: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return .{ .handler = handler, .matchFn = struct {
        fn f(method: Method, u: []const u8) bool {
            return method == m and std.mem.startsWith(u8, u, prefix);
        }
    }.f };
}

pub fn GET(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.GET, url, handler);
}

pub fn POST(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.POST, url, handler);
}

pub fn PUT(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.PUT, url, handler);
}

pub fn DELETE(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.DELETE, url, handler);
}

pub fn PATCH(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.PATCH, url, handler);
}

pub fn HEAD(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.HEAD, url, handler);
}

pub fn OPTIONS(comptime url: []const u8, handler: anytype) Route(@TypeOf(handler)) {
    return route(.OPTIONS, url, handler);
}