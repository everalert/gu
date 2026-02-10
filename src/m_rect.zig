const Rect = @This();

const std = @import("std");
const FormatOptions = std.fmt.FormatOptions;

const Vec2 = @import("m_vec2.zig");

x: f32,
y: f32,
w: f32,
h: f32,

pub const zero = Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

pub fn init(x: f32, y: f32, w: f32, h: f32) Rect {
    return Rect{ .x = x, .y = y, .w = w, .h = h };
}

pub fn toPos(r: *const Rect) Vec2 {
    return .{ .x = r.x, .y = r.y };
}

pub fn toSize(r: *const Rect) Vec2 {
    return .{ .x = r.w, .y = r.h };
}

/// compatibility with std.fmt
pub fn format(self: *const Rect, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
    try writer.print(
        "Rect(x:{d: <4} y:{d: <4} w:{d: <4} h:{d: <4})",
        .{ self.x, self.y, self.w, self.h },
    );
}

//------------------------------------------------------------------------------
// math ops

pub fn EQL(r1: *const Rect, r2: *const Rect) bool {
    return @intFromBool(r1.x == r2.x) & @intFromBool(r1.y == r2.y) &
        @intFromBool(r1.w == r2.w) & @intFromBool(r1.h == r2.h) > 0;
}

//------------------------------------------------------------------------------
// properties

pub inline fn Area(self: Rect) f32 {
    return self.w * self.h;
}

pub inline fn AreaIsNonZero(self: Rect) bool {
    return self.Area() > 0;
}

//------------------------------------------------------------------------------
// advanced math

pub fn IsCollidingPoint(self: *const Rect, pt: *const Vec2) bool {
    return (pt.x >= self.x and
        pt.x < self.x + self.w and
        pt.y >= self.y and
        pt.y < self.y + self.h);
}

pub fn IsCollidingRect(self: *const Rect, other: *const Rect) bool {
    return (self.x + self.w >= other.x and
        self.x <= other.x + other.w and
        self.y + self.h >= other.y and
        self.y <= other.y + other.h);
}

// TODO: ?? move to "math ops" section and rename to `AND`?
/// AND operation
pub fn GetIntersection(r1: *const Rect, r2: *const Rect) Rect {
    const x = @max(r1.x, r2.x);
    const y = @max(r1.y, r2.y);
    const w = @min(r1.x + r1.w, r2.x + r2.w) - x;
    const h = @min(r1.y + r1.h, r2.y + r2.h) - y;
    return Rect{ .x = x, .y = y, .w = w, .h = h };
}
