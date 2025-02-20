const std = @import("std");

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/sdl.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/sdl_main.h");
});

// errify SDL return values
pub inline fn SDLE(value: anytype) error{SDL_ERROR}!switch (@typeInfo(@TypeOf(value))) {
    .Bool => void,
    .Pointer, .Optional => @TypeOf(value.?),
    .Int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("Unerrifiable SDL type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .Bool => if (!value) error.SDL_ERROR,
        .Pointer, .Optional => value orelse error.SDL_ERROR,
        .Int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SDL_ERROR,
            .unsigned => if (value != 0) value else error.SDL_ERROR,
        },
        else => comptime unreachable,
    };
}

pub inline fn SDLTryErrorPrint(err: [:0]const u8) void {
    if (std.mem.eql(u8, err, @errorName(error.SDL_ERROR)))
        std.log.err("SDL error: {s}", .{c.SDL_GetError()});
}
