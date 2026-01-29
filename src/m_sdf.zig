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

pub fn sd_circle(p: Vec2, r: f32) f32 {
    return p.Mag() - r;
}

pub fn sd_quadratic_circle(p: Vec2, r: f32) f32 {
    const ap = p.octant().DIVS(r);

    const a: f32 = ap.x - ap.y;
    const b: f32 = ap.x + ap.y;
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
    const w = Vec2.init(-t + 0.75 - t * t - ap.x, t + 0.75 - t * t - ap.y);
    return w.Mag() * sign(a * a * 0.5 + b - 1.5) * r;
}

// TODO: more efficient algorithm, see p5js for notes/ideas
// see also: https://editor.p5js.org/everalert/sketches/yEGmV6Adg
/// N=4 A=B superellipse, via geometric search
pub fn sd_superellipse(p: Vec2, r: f32) f32 {
    @setEvalBranchQuota(5000000);
    const N: f32 = 4;
    const A: f32 = r;
    const B: f32 = r;

    const resolution: f32 = 24; // polygon density per quadrant
    const increment = @as(f32, PI) / 2 / resolution;

    const ap = p.octant();

    if (ap.EQL(Vec2.zero)) return -r;

    const point: Vec2 = pt: {
        var prev_a = @as(f32, PI) / 4;
        var prev_p = get_superellipse_xy(N, A, B, prev_a);
        var prev_d = ap.DistSq(prev_p);
        var prev_nearest = prev_p;

        while (prev_a > 0) : (prev_a -= increment) {
            const next_a = @max(0, prev_a - increment);
            const next_p = get_superellipse_xy(N, A, B, next_a);
            const nearest = ap.NearestPointOnLine(prev_p, next_p);
            const next_d = ap.DistSq(nearest);

            if (next_d > prev_d)
                break :pt prev_nearest;
            if (next_a <= 0.0)
                break :pt nearest;

            prev_nearest = nearest;
            prev_p = next_p;
            prev_d = next_d;
        } else unreachable;
    };

    return point.Dist(ap) * sign(point.vecTo(ap).Dot(ap));
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

pub fn sd_rhombus(p: Vec2, r: f32) f32 {
    const ap = p.quadrant();
    const rp: Vec2 = .init(r, -r);
    const h: f32 = clamp((rp.Dot(ap) + rp.y * rp.y) / rp.MagSq(), 0.0, 1.0);
    const op = ap.SUB(rp.MUL(.init(h, h - 1)));
    return op.Mag() * sign(op.x);
}

pub fn sd_chamfer_box(p: Vec2, r: f32) f32 {
    const MARGIN: f32 = 0.1;
    assert(r >= MARGIN * 2 + std.math.floatEpsAt(f32, MARGIN * 2));

    const chamfer: f32 = r - MARGIN; // edge is fuzzy if cutting too much
    const ap: Vec2 = p.octant().ADD(.init(-r, -r + chamfer));
    const k: f32 = 1.0 - @sqrt(2.0);

    if (ap.y < 0.0 and ap.y + ap.x * k < 0.0)
        return ap.x;
    if (ap.x < ap.y)
        return (ap.x + ap.y) * @sqrt(0.5);

    return ap.Mag();
}

// https://www.shadertoy.com/view/3lK3RG
// octagon with vertices on cardinals
pub fn sd_octagon(p: Vec2, r: f32) f32 {
    const R = r * @cos(@as(f32, PI) / 8);
    const k: [4]f32 = .{
        -0.9238795325, // sqrt(2+sqrt(2))/2  // COS PI/8
        0.3826834323, //  sqrt(2-sqrt(2))/2  // SIN PI/8
        0.4142135623, //  sqrt(2)-1          // TAN PI/8
        0.7071067812, //  1/sqrt(2)          // SIN PI/4
    };

    var ap = p.quadrant();
    const off1 = Vec2.init(k[3], -k[3]);
    ap = ap.SUB(Vec2.initSquare(2.0 * @min(off1.Dot(ap), 0.0)).MUL(off1));
    ap = Vec2.init(ap.Dot(Vec2.init(-k[1], -k[0])), ap.Dot(Vec2.init(-k[0], k[1])));
    ap = ap.SUB(Vec2.init(clamp(ap.x, -k[2] * R, k[2] * R), R));
    return ap.Mag() * sign(ap.y);
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
    fn_sdf: *const fn (p: Vec2, r: f32) f32,
) void {
    assert(field.len == radius * radius * 4);

    const width = radius * 2;
    const middle = radius - 1;
    for (0..radius) |y| {
        for (0..radius) |x| {
            @setEvalBranchQuota(1000000);
            const sd = fn_sdf(.init(x, y), radius);
            field[middle - x + (middle - y) * width] = sd; // tl
            field[x + radius + (middle - y) * width] = sd; // tr
            field[middle - x + (y + radius) * width] = sd; // bl
            field[x + radius + (y + radius) * width] = sd; // br
        }
    }
}
