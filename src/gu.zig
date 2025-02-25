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

pub const GUColor = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    // WARN: assumes big-endian
    pub fn FromInt(color: u32) GUColor {
        return @bitCast(@byteSwap(color));
    }
};

pub const GUBackend = struct {
    ptr: *anyopaque,
    fnDrawRect: *const fn (*anyopaque, *const GURect, u32) void,
    fnDrawString: *const fn (*anyopaque, *GUFontAtlas, *const GUPos, []const u8, u32) void,
    fnDrawImage: *const fn (*anyopaque, *GUTextureAtlas, *const GUPos, u32) void,

    pub fn DrawRect(self: *GUBackend, rect: *const GURect, color: u32) void {
        self.fnDrawRect(self.ptr, rect, color);
    }

    pub fn DrawString(self: *GUBackend, tex: *GUFontAtlas, pos: *const GUPos, str: []const u8, color: u32) void {
        self.fnDrawString(self.ptr, tex, pos, str, color);
    }

    // TODO: impl tile drawing, see GURenderCommand->Image
    pub fn DrawImage(self: *GUBackend, tex: *GUTextureAtlas, pos: *const GUPos, color: u32) void {
        self.fnDrawImage(self.ptr, tex, pos, color);
    }
};

pub const GURenderCommand = union(enum) {
    Rect: struct {
        rect: GURect,
        color: u32,
    },
    Text: struct {
        str: []const u8,
        font: *GUFontAtlas,
        pos: GUPos,
        color: u32,
    },
    Image: struct {
        image: *GUTextureAtlas,
        tile: ?u32, // for texture atlases
        pos: GUPos,
        color: u32,
    },
};

// TODO: add CanDrawString to check against supported character range in font impl
pub const GUFontAtlas = struct {
    ptr: *anyopaque,
    fnDrawString: *const fn (*anyopaque, []const u8, *const GUPos) void,
    fnDrawChar: *const fn (*anyopaque, u8, *const GUPos) void,
    fnStringSize: *const fn (*anyopaque, []const u8) GUSize,
    fnCharSize: *const fn (*anyopaque, u8) GUSize,
    fnSetColor: *const fn (*anyopaque, u32) void,

    pub fn DrawString(self: *GUFontAtlas, str: []const u8, pos: *const GUPos) void {
        self.fnDrawString(self.ptr, str, pos);
    }

    pub fn DrawChar(self: *GUFontAtlas, char: u8, pos: *const GUPos) void {
        self.fnDrawChar(self.ptr, char, pos);
    }

    pub fn StringSize(self: *GUFontAtlas, str: []const u8) GUSize {
        return self.fnStringSize(self.ptr, str);
    }

    pub fn CharSize(self: *GUFontAtlas, char: u8) GUSize {
        return self.fnCharSize(self.ptr, char);
    }

    pub fn SetColor(self: *GUFontAtlas, color: u32) void {
        return self.fnSetColor(self.ptr, color);
    }
};

pub const GUTextureAtlas = struct {
    ptr: *anyopaque,
    fnDraw: *const fn (*anyopaque, *const GUPos) void,
    fnDrawTile: *const fn (*anyopaque, u32, *const GUPos) void,
    fnSize: *const fn (*anyopaque) GUSize,
    fnTileSize: *const fn (*anyopaque, u32) GUSize,
    fnSetColor: *const fn (*anyopaque, u32) void,

    pub fn Draw(self: *GUTextureAtlas, pos: *const GUPos) void {
        self.fnDraw(self.ptr, pos);
    }

    pub fn DrawTile(self: *GUTextureAtlas, id: u32, pos: *const GUPos) void {
        self.fnDrawTile(self.ptr, id, pos);
    }

    pub fn Size(self: *GUTextureAtlas) GUSize {
        return self.fnSize(self.ptr);
    }

    pub fn TileSize(self: *GUTextureAtlas, id: u32) GUSize {
        return self.fnTileSize(self.ptr, id);
    }

    pub fn SetColor(self: *GUTextureAtlas, color: u32) void {
        return self.fnSetColor(self.ptr, color);
    }
};

pub const GUButton = struct {
    const PADDING_VERTICAL: f32 = 2;
    const PADDING_HORIZONTAL: f32 = 8;

    mode: enum(u32) { Press, Release } = .Press,
    state: enum(u32) { Idle, Hover, Down } = .Idle,

    pub fn Update(
        self: *GUButton,
        rect: *const GURect,
        pt: *const GUPos,
        btn_just_down: bool,
        btn_just_up: bool,
    ) bool {
        if (rect.PointInRect(pt)) {
            if (self.state == .Idle)
                self.state = .Hover;

            if (self.state == .Hover and btn_just_down) {
                self.state = .Down;
                if (self.mode == .Press) {
                    std.log.debug("button activated! (press)", .{});
                    return true;
                }
            }

            if (self.state == .Down and btn_just_up) {
                self.state = .Hover;
                if (self.mode == .Release) {
                    std.log.debug("button activated! (release)", .{});
                    return true;
                }
            }
        } else {
            self.state = .Idle;
        }
        return false;
    }
};

// TODO: rename to GUKeyState?
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

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles
images: ArrayList(GUTextureAtlas), // TODO: impl with handles
render_commands: ArrayList(GURenderCommand),

mouse_pt: GUPos = .{ .x = -1, .y = -1 },
mouse_left: GUButtonState = .{}, // LMB

pub fn Init(alloc: Allocator, backend: GUBackend) GU {
    return .{
        .allocator = alloc,
        .backend = backend,
        .fonts = ArrayList(GUFontAtlas).init(alloc),
        .images = ArrayList(GUTextureAtlas).init(alloc),
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

pub fn EndFrame(self: *GU) void {
    for (self.render_commands.items) |command| {
        switch (command) {
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
        }
    }
}

pub fn DoLabel(self: *GU, x: f32, y: f32, font: ?usize, color: ?u32, str: []const u8) !void {
    std.debug.assert(self.fonts.items.len >= (font orelse 1));
    try self.render_commands.append(.{
        .Text = .{
            .pos = .{ .x = x, .y = y },
            .font = &self.fonts.items[font orelse 0],
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
            .image = &self.images.items[image orelse 0],
            .color = color orelse 0xFFFFFFFF,
            .tile = null,
        },
    });
}

/// returns whether button was 'activated' (pressed)
pub fn DoButton(self: *GU, btn: *GUButton, x: f32, y: f32, font: ?usize, str: []const u8) !bool {
    const f = &self.fonts.items[font orelse 0];
    const str_size = f.StringSize(str);
    const rect = GURect{
        .x = x,
        .y = y,
        .w = GUButton.PADDING_HORIZONTAL * 2 + str_size.w,
        .h = GUButton.PADDING_VERTICAL * 2 + str_size.h,
    };

    const output = btn.Update(&rect, &self.mouse_pt, self.mouse_left.just_down, self.mouse_left.just_up);

    switch (btn.state) {
        .Idle => try self.DoRect(rect.x, rect.y, rect.w, rect.h, 0x008000FF),
        .Hover => try self.DoRect(rect.x, rect.y, rect.w, rect.h, 0x00C000FF),
        .Down => try self.DoRect(rect.x, rect.y, rect.w, rect.h, 0x004000FF),
    }
    try self.DoLabel(
        rect.x + GUButton.PADDING_HORIZONTAL,
        rect.y + GUButton.PADDING_VERTICAL,
        null,
        null,
        str,
    );

    return output;
}

// TODO: impl handle-based system
pub fn AddFont(self: *GU, font: GUFontAtlas) !usize {
    try self.fonts.append(font);
    return self.fonts.items.len - 1;
}

// TODO: impl handle-based system
pub fn AddImage(self: *GU, image: GUTextureAtlas) !usize {
    try self.images.append(image);
    return self.images.items.len - 1;
}
