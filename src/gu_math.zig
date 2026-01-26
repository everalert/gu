const std = @import("std");

const FormatOptions = std.fmt.FormatOptions;

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub const Zero = Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

    pub fn IsCollidingPoint(self: *const Rect, pt: *const Pos) bool {
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

    pub inline fn HasNonZeroArea(self: *const Rect) bool {
        return self.w * self.h > 0;
    }

    pub inline fn GetSmallestDimension(self: *const Rect) f32 {
        return @min(self.w, self.h);
    }

    /// AND operation
    pub fn GetIntersection(r1: *const Rect, r2: *const Rect) Rect {
        const x = @max(r1.x, r2.x);
        const y = @max(r1.y, r2.y);
        const w = @min(r1.x + r1.w, r2.x + r2.w) - x;
        const h = @min(r1.y + r1.h, r2.y + r2.h) - y;
        return Rect{ .x = x, .y = y, .w = w, .h = h };
    }

    /// compatibility with std.fmt
    pub fn format(self: *const Rect, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        try writer.print(
            "GURect(x:{d: <4} y:{d: <4} w:{d: <4} h:{d: <4})",
            .{ self.x, self.y, self.w, self.h },
        );
    }
};

// TODO: rename to GUPoint?
pub const Pos = struct {
    x: f32,
    y: f32,

    pub const Zero = Pos{ .x = 0, .y = 0 };

    pub fn FromRect(rect: *const Rect) Pos {
        return Pos{ .x = rect.x, .y = rect.y };
    }
};

pub const Size = struct {
    w: f32,
    h: f32,

    pub const Zero = Size{ .w = 0, .h = 0 };

    pub fn FromRect(rect: *const Rect) Size {
        return Size{ .w = rect.w, .h = rect.h };
    }

    pub inline fn HasNonZeroArea(self: *const Size) bool {
        return self.w * self.h > 0;
    }
};

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    // WARN: assumes big-endian
    pub fn FromInt(color: u32) Color {
        return @bitCast(@byteSwap(color));
    }
};
