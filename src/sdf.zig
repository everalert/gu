const std = @import("std");

const assert = std.debug.assert;
const clamp = std.math.clamp;
const pow = std.math.pow;
const sign = std.math.sign;

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

// FIXME: doesn't really work well (or at all, for some N values). maybe another
//  binary search style approach would be to check the dot product between the
//  curve normal tangent and the curve-to-point vector, otherwise just bite the
//  bullet and do newtonian iteration
// binary search-based sdf approximation for a==b superellipse
pub fn sd_superellipse(x: f32, y: f32, r: f32) f32 {
    @setEvalBranchQuota(2000000);
    const ax = @max(@abs(x), @abs(y));
    const ay = @min(@abs(x), @abs(y));

    const N: f32 = 4;
    const na = 2 / N;

    var st_a: f32 = 0; // angle
    var st_x: f32 = r * pow(f32, @cos(st_a), na);
    var st_y: f32 = r * pow(f32, @sin(st_a), na);
    var st_d = (st_x - ax) * (st_x - ax) + (st_y - ay) * (st_y - ay); // dist

    var ed_a: f32 = @as(f32, std.math.pi) / 4;
    var ed_x: f32 = r * pow(f32, @cos(ed_a), na);
    var ed_y: f32 = r * pow(f32, @sin(ed_a), na);
    var ed_d = (ed_x - ax) * (ed_x - ax) + (ed_y - ay) * (ed_y - ay);

    while (((ed_x - st_x) * (ed_x - st_x) + (ed_y - st_y) * (ed_y - st_y)) > 0.01) {
        const next_a = st_a * 0.5 + ed_a * 0.5;
        if (st_d > ed_d) {
            st_a = next_a;
            st_x = r * pow(f32, @cos(st_a), na); // * sign(@cos(st_a));
            st_y = r * pow(f32, @sin(st_a), na); // * sign(@sin(st_a));
            st_d = (st_x - ax) * (st_x - ax) + (st_y - ay) * (st_y - ay);
        } else {
            ed_a = next_a;
            ed_x = r * pow(f32, @cos(ed_a), na); // * sign(@cos(ed_a));
            ed_y = r * pow(f32, @sin(ed_a), na); // * sign(@sin(ed_a));
            ed_d = (ed_x - ax) * (ed_x - ax) + (ed_y - ay) * (ed_y - ay);
        }
    }

    const pt_d = ax * ax + ay * ay;
    const st_0d = st_x * st_x + st_y * st_y;
    return @sqrt(if (pt_d < st_0d) -st_d else st_d);
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
