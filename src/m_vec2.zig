const Vec2 = @This();

const std = @import("std");
const clamp = std.math.clamp;

x: f32,
y: f32,

pub const zero: Vec2 = .{ .x = 0, .y = 0 };

pub fn init(x: f32, y: f32) Vec2 {
    return Vec2{ .x = x, .y = y };
}

pub fn initSquare(r: f32) Vec2 {
    return Vec2{ .x = r, .y = r };
}

pub fn vecTo(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v2.x - v1.x, .y = v2.y - v1.y };
}

pub fn inv(v: Vec2) Vec2 {
    return Vec2{ .x = -v.x, .y = -v.y };
}

pub fn octant(v: Vec2) Vec2 {
    return Vec2{ .x = @max(@abs(v.x), @abs(v.y)), .y = @min(@abs(v.x), @abs(v.y)) };
}

pub fn quadrant(v: Vec2) Vec2 {
    return Vec2{ .x = @abs(v.x), .y = @abs(v.y) };
}

//------------------------------------------------------------------------------
// math ops

pub fn ADD(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x + v2.x, .y = v1.y + v2.y };
}

/// add scalar
pub fn ADDS(v: Vec2, s: f32) Vec2 {
    return Vec2{ .x = v.x + s, .y = v.y + s };
}

pub fn SUB(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x - v2.x, .y = v1.y - v2.y };
}

/// subtract scalar
pub fn SUBS(v: Vec2, s: f32) Vec2 {
    return Vec2{ .x = v.x - s, .y = v.y - s };
}

// TODO: remove, or alias Dot?
pub fn MUL(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x * v2.x, .y = v1.y * v2.y };
}

/// multiply scalar
pub fn MULS(v: Vec2, s: f32) Vec2 {
    return Vec2{ .x = v.x * s, .y = v.y * s };
}

pub fn DIV(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x / v2.x, .y = v1.y / v2.y };
}

/// divide scalar
pub fn DIVS(v: Vec2, s: f32) Vec2 {
    return Vec2{ .x = v.x / s, .y = v.y / s };
}

pub fn EQL(v1: Vec2, v2: Vec2) bool {
    return v1.x == v2.x and v1.y == v2.y;
}

pub fn CLAMP(v: Vec2, min: Vec2, max: Vec2) Vec2 {
    return Vec2{ .x = clamp(v.x, min.x, max.x), .y = clamp(v.y, min.y, max.y) };
}

pub fn MIN(v: Vec2, min: Vec2) Vec2 {
    return Vec2{ .x = @min(v.x, min.x), .y = @min(v.y, min.y) };
}

pub fn MAX(v: Vec2, max: Vec2) Vec2 {
    return Vec2{ .x = @max(v.x, max.x), .y = @max(v.y, max.y) };
}

//------------------------------------------------------------------------------
// vector properties

pub inline fn Dist(v1: Vec2, v2: Vec2) f32 {
    return @sqrt(v1.DistSq(v2));
}

pub inline fn DistSq(v1: Vec2, v2: Vec2) f32 {
    return MagSq(vecTo(v1, v2));
}

pub inline fn Mag(v: Vec2) f32 {
    return @sqrt(v.MagSq());
}

pub inline fn MagSq(v: Vec2) f32 {
    return v.x * v.x + v.y * v.y;
}

pub inline fn Dot(v1: Vec2, v2: Vec2) f32 {
    return v1.x * v2.x + v1.y * v2.y;
}

pub inline fn Area(v: Vec2) f32 {
    return v.x * v.y;
}

//------------------------------------------------------------------------------
// advanced math

pub fn NearestPointOnLine(p: Vec2, v: Vec2, w: Vec2) Vec2 {
    const vp = v.vecTo(p);
    const vw = v.vecTo(w);
    const vw_len_sq = vw.MagSq();
    if (vw_len_sq == 0.0) return vp;
    const t = clamp(vp.Dot(vw) / vw_len_sq, 0, 1);
    return v.ADD(vw.MULS(t));
}
