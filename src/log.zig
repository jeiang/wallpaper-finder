const std = @import("std");

var global_log_level: std.log.Level = .err;

pub fn setLogLevel(level: std.log.Level) void {
    global_log_level = level;
}

pub fn customLogger(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // if more verbose than current log level, skip
    if (@intFromEnum(level) > @intFromEnum(global_log_level)) {
        return;
    }

    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";

    const level_text = comptime blk: {
        const inner = level.asText();
        var buf = [_]u8{0} ** inner.len;
        for (0.., &buf) |idx, *char| {
            char.* = std.ascii.toUpper(inner[idx]);
        }
        break :blk buf;
    };

    const prefix = "[" ++ level_text ++ "] " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}
