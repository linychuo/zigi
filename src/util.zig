const std = @import("std");

pub fn decodePercent(s: []const u8, allocator: std.mem.Allocator) ?[]u8 {
    var result = allocator.alloc(u8, s.len) catch return null;
    errdefer allocator.free(result);
    var j: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hex = s[i + 1..i + 3];
            if (std.fmt.parseInt(u8, hex, 16)) |val| {
                result[j] = val;
                j += 1;
                i += 2;
            } else |_| {
                result[j] = s[i];
                j += 1;
            }
        } else {
            result[j] = s[i];
            j += 1;
        }
    }
    if (j < s.len) {
        const shorter = allocator.realloc(result, j) catch result;
        result = shorter;
    }
    return result;
}

pub fn decodeChunkedBody(stream: anytype, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    while (true) {
        var size_buf: [32]u8 = undefined;
        var size_len: usize = 0;

        while (size_len < size_buf.len) {
            const n = try stream.read(size_buf[size_len..1]);
            if (n == 0) return error.ConnectionClosed;
            size_len += n;
            if (size_len >= 2 and size_buf[size_len - 1] == '\n' and size_buf[size_len - 2] == '\r') break;
        }

        if (size_len < 3) break;

        const chunk_size = std.fmt.parseUnsigned(usize, std.mem.trim(u8, size_buf[0..size_len - 2], " \t"), 16) catch 0;
        if (chunk_size == 0) break;
        if (result.items.len + chunk_size > max_size) return error.BodyTooLarge;

        try result.ensureUnusedCapacity(chunk_size);
        const n = try stream.readAtLeast(result.unusedCapacitySlice(), chunk_size);
        result.items.len += n;

        _ = try stream.read(&[_]u8{ 0, 0 });
    }

    return try result.toOwnedSlice();
}