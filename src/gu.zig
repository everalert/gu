const GU = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const GURect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn PointInRect(self: *const GURect, pt: *const GUPos) bool {
        return pt.x >= self.x and pt.x < self.x + self.w and
            pt.y >= self.y and pt.y < self.y + self.h;
    }
};

// TODO: rename to GUPoint?
pub const GUPos = struct {
    x: f32,
    y: f32,
};

pub const GUSize = struct {
    w: f32,
    h: f32,
};

const GURenderCommand = union(enum) {
    Rect: struct {
        rect: GURect,
        color: u32,
    },
    Text: struct {
        str: []const u8,
        font: *anyopaque, // backend impl-dependent ref to resource
        pos: GUPos,
        color: u32,
    },
    Image: struct {
        image: *anyopaque, // backend impl-dependent ref to resource
        tile: ?u32, // for texture atlases
        pos: GUPos,
        color: u32,
    },
};

pub const GUButtonState = struct {
    down: bool = false,
    just_up: bool = false,
    just_down: bool = false,
    accumulator_down: bool = false,
    accumulator_changes: u32 = 0,

    pub fn Accumulate(self: *GUButtonState, down: bool) void {
        if (self.accumulator_down != down) {
            self.accumulator_down = down;
            self.accumulator_changes += 1;
        }
    }

    pub fn Update(self: *GUButtonState) void {
        self.just_down = (self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.just_up = (!self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.down = self.accumulator_down;
        self.accumulator_changes = 0;
    }
};

allocator: Allocator,

fonts: ArrayList(*anyopaque), // TODO: impl with handles + interface-based payload
images: ArrayList(*anyopaque), // TODO: impl with handles + interface-based payload
render_commands: ArrayList(GURenderCommand),

mouse_pt: GUPos = .{ .x = -1, .y = -1 },
mouse_left: GUButtonState = .{}, // LMB

pub fn Init(alloc: Allocator) GU {
    return .{
        .allocator = alloc,
        .fonts = ArrayList(*anyopaque).init(alloc),
        .images = ArrayList(*anyopaque).init(alloc),
        .render_commands = ArrayList(GURenderCommand).init(alloc),
    };
}

pub fn Deinit(self: *GU) void {
    self.render_commands.deinit();
    self.images.deinit();
    self.fonts.deinit();
}

pub fn BeginFrame(self: *GU) void {
    self.render_commands.clearRetainingCapacity();
    self.mouse_left.Update();
}

//pub fn EndFrame(self: *GU) void {
//    _ = self;
//}

pub fn DoLabel(self: *GU, x: f32, y: f32, font: ?usize, color: ?u32, str: []const u8) !void {
    std.debug.assert(self.fonts.items.len >= (font orelse 1));
    try self.render_commands.append(.{
        .Text = .{
            .pos = .{ .x = x, .y = y },
            .font = self.fonts.items[font orelse 0],
            .color = color orelse 0xFFFFFFFF,
            .str = str,
        },
    });
}

pub fn DoRect(self: *GU, x: f32, y: f32, w: f32, h: f32, color: ?u32) !void {
    try self.render_commands.append(.{
        .Rect = .{
            .rect = .{ .x = x, .y = y, .w = w, .h = h },
            .color = color orelse 0xFFFFFFFF,
        },
    });
}

pub fn DoImage(self: *GU, x: f32, y: f32, image: ?usize, color: ?u32) !void {
    std.debug.assert(self.images.items.len >= (image orelse 1));
    try self.render_commands.append(.{
        .Image = .{
            .pos = .{ .x = x, .y = y },
            .image = self.images.items[image orelse 0],
            .color = color orelse 0xFFFFFFFF,
            .tile = null,
        },
    });
}

// TODO: impl handle-based system
pub fn AddFont(self: *GU, font: *anyopaque) !usize {
    try self.fonts.append(font);
    return self.fonts.items.len - 1;
}

// TODO: impl handle-based system
pub fn AddImage(self: *GU, image: *anyopaque) !usize {
    try self.images.append(image);
    return self.images.items.len - 1;
}
