const std = @import("std");

const assert = std.debug.assert;
const clamp = std.math.clamp;
const pow = std.math.pow;
const sign = std.math.sign;
const PI = std.math.pi;
const TAU = std.math.tau;

const Vec2 = @import("m_vec2.zig");

// mostly attributable to the classic:
// https://iquilezles.org/articles/distfunctions2d/

// TODO: finish superellipse sdf, or some acceptable approximation. should be
//  stable up to +/- 1px for an 8px radius. even if the function is extremely
//  expensive, having something means it can be used to generate a LUT
// TODO: SDF LUT sampler. given a grid of pre-calculated distance values, return
//  an interpolated value when queried with an arbitrary "subpixel" point
// TODO: SDF interpolating sampler. given two or more sdf samplers, map these
//  samplers each to a numerical value, and provide a sampler that interpolates
//  between samples of the same input point. may be used for animating transitions
//  between sdf outputs, e.g. a series of precalculated superellipse sdf samplers
//  for different values of N, or between a circle and a quadratic circle.

//------------------------------------------------------------------------------
// distance functions

// NOTE: for now, all functions assume a square field that can be defined by a
//  radius only, for the purpose of callback-oriented api symmetry.

pub fn sd_circle(x: f32, y: f32, r: f32) f32 {
    return @sqrt(x * x + y * y) - r;
}

pub fn sd_quadratic_circle(x: f32, y: f32, r: f32) f32 {
    const ax = @abs(if (y > x) y else x) / r;
    const ay = @abs(if (y > x) x else y) / r;

    const a: f32 = ax - ay;
    const b: f32 = ax + ay;
    const d: f32 = (2.0 * b - 1.0) / 3.0;
    var h: f32 = a * a + d * d * d;
    var t: f32 = 0;
    if (h >= 0.0) {
        @setEvalBranchQuota(1000000);
        h = @sqrt(h);
        t = sign(h - a) *
            pow(f32, @abs(h - a), 1.0 / 3.0) -
            pow(f32, h + a, 1.0 / 3.0);
    } else {
        const z = @sqrt(-d);
        const v = std.math.acos(a / (d * z)) / 3.0;
        t = -z * (@cos(v) + @sin(v) * 1.732050808);
    }
    t *= 0.5;
    const wx = -t + 0.75 - t * t - ax;
    const wy = t + 0.75 - t * t - ay;
    return @sqrt(wx * wx + wy * wy) * sign(a * a * 0.5 + b - 1.5) * r;
}

// TODO: fix edge smoothness. algo favours full pixels too readily, causing a
//  slightly "chunky" look overall, even with a very high resolution. this is
//  most noticeable at the "straight" parts with a higher N, but even when N=2
//  the edge smoothness is noticeably lower than sd_circle with the same radius.
//  for now, using a lower resolution can look a little more appealing, but does
//  so by introducing minor dithering, so this is not a solution. the ongoing
//  work on fixing the algo is at `Vec2.NearestPointOnLine_v2`
// TODO: use resolution=24 once rendering issues fixed
// TODO: more efficient algorithm, see p5js for notes/ideas
// see also: https://editor.p5js.org/everalert/sketches/yEGmV6Adg
/// N=4 A=B superellipse, via geometric search
pub fn sd_superellipse(x: f32, y: f32, r: f32) f32 {
    @setEvalBranchQuota(5000000);
    const N: f32 = 4;
    const A: f32 = r;
    const B: f32 = r;

    const resolution: f32 = 28; // polygon density per quadrant
    const increment = @as(f32, PI) / 2 / resolution;

    const p = Vec2{
        .x = @max(@abs(x), @abs(y)),
        .y = @min(@abs(x), @abs(y)),
    };

    var prev_a = @as(f32, PI) / 4;
    var prev_p = get_superellipse_xy(N, A, B, prev_a);
    var prev_d = (@max(A, B, r * 2)) * (@max(A, B, r * 2)) * (@max(A, B, r * 2));
    const point: Vec2, const dist_np_sq: f32 =
        pt: while (prev_a > 0) : (prev_a -= increment) {
            const next_a = @max(0, prev_a - increment);
            const next_p = get_superellipse_xy(N, A, B, next_a);
            const np = p.NearestPointOnLine(prev_p, next_p);
            const next_d = p.DistSq(np);
            if (next_d > prev_d) break :pt .{ prev_p, prev_d };
            if (next_a <= 0.0) break :pt .{ np, next_d };
            prev_p = next_p;
            prev_d = next_d;
        } else unreachable;

    const dist_np = @sqrt(dist_np_sq);
    return if (p.MagSq() > point.MagSq()) dist_np else -dist_np;
}

/// @angle      radians
fn get_superellipse_xy(n: f32, a: f32, b: f32, angle: f32) Vec2 {
    const ca = @cos(angle);
    const sa = @sin(angle);
    const na = 2 / n;
    return Vec2{
        .x = a * pow(f32, @abs(ca), na) * sign(ca),
        .y = b * pow(f32, @abs(sa), na) * sign(sa),
    };
}

pub fn sd_rhombus(x: f32, y: f32, r: f32) f32 {
    const ax = @abs(x);
    const ay = @abs(y);
    const rx = r;
    const ry = -r;
    const dot_r = rx * rx + ry * ry;
    const dot_bp = rx * ax + ry * ay;
    const h: f32 = clamp((dot_bp + ry * ry) / dot_r, 0.0, 1.0);
    const ox = ax - rx * h;
    const oy = ay - ry * (h - 1);
    return @sqrt(ox * ox + oy * oy) * sign(ox);
}

pub fn sd_chamfer_box(x: f32, y: f32, r: f32) f32 {
    assert(r >= 2);
    const chamfer: f32 = r - 1; // edge is fuzzy if cutting too much

    const ax = @abs(if (y > x) y else x) - r;
    const ay = @abs(if (y > x) x else y) - r + chamfer;
    const k: f32 = 1.0 - @sqrt(2.0);

    if (ay < 0.0 and ay + ax * k < 0.0)
        return ax;

    if (ax < ay)
        return (ax + ay) * @sqrt(0.5);

    return @sqrt(ax * ax + ay * ay);
}

// https://www.shadertoy.com/view/3lK3RG
// octagon with vertices on cardinals
pub fn sd_octagon(x: f32, y: f32, r: f32) f32 {
    const k: [4]f32 = .{
        -0.9238795325, // sqrt(2+sqrt(2))/2  // COS PI/8
        0.3826834323, // sqrt(2-sqrt(2))/2  // SIN PI/8
        0.4142135623, // sqrt(2)-1          // TAN PI/8
        0.7071067812, // 1/sqrt(2)          // SIN PI/4
    };

    var ax = @abs(x);
    var ay = @abs(y);

    const dot1 = ax * k[3] + ay * -k[3];
    ax -= 2.0 * @min(dot1, 0.0) * k[3]; // Reflect about pi/4 plane
    ay -= 2.0 * @min(dot1, 0.0) * -k[3];

    const dot2 = ax * -k[1] + ay * -k[0];
    const dot3 = ax * -k[0] + ay * k[1];
    ax = dot2; // Rotate by 22.5 degrees
    ay = dot3;

    ax -= clamp(ax, -k[2] * r, k[2] * r); // Collapse the polygon edge to a point
    ay -= r;

    return @sqrt(ax * ax + ay * ay) * sign(ay);
}

//------------------------------------------------------------------------------
// utility

/// generate all the values for quadrant I (+x,+y), and mirror them in the output
/// across both axes such that the "corner" becomes a "square". generally produces
/// superior results to mapping the whole range for whole pixel coordinates, as
/// the quadrants are guaranteed to have pixel-level symmetry while using the
/// most robust quadrant for pixels.
pub fn render_whole_from_quadrant(
    radius: u32,
    field: []f32,
    fn_sdf: *const fn (x: f32, y: f32, r: f32) f32,
) void {
    assert(field.len == radius * radius * 4);

    const width = radius * 2;
    const middle = radius - 1;
    for (0..radius) |y| {
        for (0..radius) |x| {
            @setEvalBranchQuota(1000000);
            const sd = fn_sdf(x, y, radius);
            field[middle - x + (middle - y) * width] = sd; // tl
            field[x + radius + (middle - y) * width] = sd; // tr
            field[middle - x + (y + radius) * width] = sd; // bl
            field[x + radius + (y + radius) * width] = sd; // br
        }
    }
}
