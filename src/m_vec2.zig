const Vec2 = @This();

const std = @import("std");
const clamp = std.math.clamp;

x: f32,
y: f32,

pub const zero: Vec2 = .{ .x = 0, .y = 0 };

pub fn vecTo(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v2.x - v1.x, .y = v2.y - v1.y };
}

//------------------------------------------------------------------------------
// math ops

pub fn ADD(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x + v2.x, .y = v1.y + v2.y };
}

pub fn SUB(v1: Vec2, v2: Vec2) Vec2 {
    return Vec2{ .x = v1.x - v2.x, .y = v1.y - v2.y };
}

/// multiply scalar
pub fn MULS(v: Vec2, s: f32) Vec2 {
    return Vec2{ .x = v.x * s, .y = v.y * s };
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

// FIXME: bad, not integrating well for sdf usage
//  - based on https://www.shadertoy.com/view/wdBXRW
pub fn NearestPointOnLine_v2(p: Vec2, v: Vec2, w: Vec2) Vec2 {
    const vp = v.vecTo(p);
    const vw = v.vecTo(w);
    return vp.SUB(vw.MULS(clamp(vp.Dot(vw) / vw.MagSq(), 0, 1)));
}

pub fn NearestPointOnLine(p: Vec2, v: Vec2, w: Vec2) Vec2 {
    const vp = v.vecTo(p);
    const vw = v.vecTo(w);
    const vw_len_sq = vw.MagSq();
    if (vw_len_sq == 0.0) return vp;
    const t = clamp(vp.Dot(vw) / vw_len_sq, 0, 1);
    return v.ADD(vw.MULS(t));
}
