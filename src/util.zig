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
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    errdefer result.deinit(allocator);

    while (true) {
        var size_buf: [64]u8 = undefined; // Increased buffer for larger chunk sizes
        var size_len: usize = 0;

        // Read chunk size line with proper validation
        while (size_len < size_buf.len) {
            const n = try stream.read(size_buf[size_len..1]);
            if (n == 0) return error.ConnectionClosed;
            size_len += n;

            // Check for CRLF terminator
            if (size_len >= 2 and size_buf[size_len - 1] == '\n' and size_buf[size_len - 2] == '\r') {
                break;
            }

            // Prevent infinite chunk size lines
            if (size_len > 32) {
                return error.InvalidRequest;
            }
        }

        if (size_len < 3) break; // Minimum: "0\r\n"

        // Parse chunk size, ignoring extensions after semicolon
        var chunk_size_str = std.mem.trim(u8, size_buf[0..size_len - 2], " \t");
        if (std.mem.indexOfScalar(u8, chunk_size_str, ';')) |semicolon_pos| {
            chunk_size_str = chunk_size_str[0..semicolon_pos];
        }

        const chunk_size = std.fmt.parseUnsigned(usize, chunk_size_str, 16) catch {
            return error.InvalidRequest;
        };

        if (chunk_size == 0) break; // Last chunk

        if (result.items.len + chunk_size > max_size) {
            return error.BodyTooLarge;
        }

        try result.ensureUnusedCapacity(allocator, chunk_size);
        const n = try stream.readAtLeast(result.unusedCapacitySlice(), chunk_size);
        if (n < chunk_size) {
            return error.ConnectionClosed;
        }
        result.items.len += n;

        // Read and validate chunk terminator CRLF
        var crlf_buf: [2]u8 = undefined;
        const crlf_read = try stream.read(crlf_buf[0..]);
        if (crlf_read != 2 or crlf_buf[0] != '\r' or crlf_buf[1] != '\n') {
            return error.InvalidRequest;
        }
    }

    return try result.toOwnedSlice(allocator);
}