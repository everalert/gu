const std = @import("std");

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/sdl.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/sdl_main.h");
});

pub const SDLError = error{SDL_ERROR};

// errify SDL return values
pub inline fn SDLE(value: anytype) SDLError!switch (@typeInfo(@TypeOf(value))) {
    .Bool => void,
    .Pointer, .Optional, .Int => @TypeOf(value.?),
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

// SDLE Panic
pub inline fn SDLEP(value: anytype) switch (@typeInfo(@TypeOf(value))) {
    .Bool => void,
    .Pointer, .Optional, .Int => @TypeOf(value.?),
    else => @compileError("Unerrifiable SDL type: " ++ @typeName(@TypeOf(value))),
} {
    return SDLE(value) catch |err| {
        SDLTryErrorPrint(@errorName(err));
        unreachable;
    };
}

pub inline fn SDLTryErrorPrint(err: [:0]const u8) void {
    if (std.mem.eql(u8, err, @errorName(error.SDL_ERROR)))
        std.log.err("SDL Error: {s}", .{c.SDL_GetError()});
}
