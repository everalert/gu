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
    fnGetSurfaceDimensions: *const fn (*anyopaque) GUSize,
    fnDrawRect: *const fn (*anyopaque, *const GURect, u32) void,
    fnDrawString: *const fn (*anyopaque, *GUFontAtlas, *const GUPos, []const u8, u32) void,
    fnDrawImage: *const fn (*anyopaque, *GUTextureAtlas, *const GUPos, u32) void,

    pub fn GetSurfaceDimensions(self: *GUBackend) GUSize {
        return self.fnGetSurfaceDimensions(self.ptr);
    }

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

pub const GUElementType = enum(u32) { None, LayoutBlock, Rect, Image, Label, Button };

// intended to pass forward some info to help make layout decisions
pub const GUElementData = struct {
    element: GUElementType,
    size: GUSize,
};

pub const GULayout = struct {
    //bg: ?u32 = null,
    widths: ?[]const f32 = null,
    //heights: ?[]const f32,
    //padding: ?GUSize,
    //gaps: ?GUSize,
    //scroll: ?
};

pub const GULayoutBlock = struct {
    area: GURect,
    layout: GULayout,
    row_elements: u32,
    row_max_height: f32,

    pub inline fn RowMaxHeightIncrement(self: *GULayoutBlock, height: f32) void {
        std.debug.assert(height > 0);
        self.row_max_height = @max(self.row_max_height, height);
    }
};

const GUPositionOverride = union(enum) {
    Skip: void,
    NewLine: void,
    Position: GUPos,
    Offset: GUSize,
};

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles
images: ArrayList(GUTextureAtlas), // TODO: impl with handles

layout_blocks: ArrayList(GULayoutBlock),
base_layout: GULayout,

render_commands: ArrayList(GURenderCommand),
render_pos: GUPos,
render_block: *GULayoutBlock,
render_element: GUElementData,
render_override: ?GUPositionOverride,

mouse_pt: GUPos,
mouse_left: GUButtonState, // LMB

pub fn Init(alloc: Allocator, backend: GUBackend, base_layout: ?GULayout) GU {
    return std.mem.zeroInit(GU, .{
        .allocator = alloc,
        .backend = backend,
        .fonts = ArrayList(GUFontAtlas).init(alloc),
        .images = ArrayList(GUTextureAtlas).init(alloc),
        .render_commands = ArrayList(GURenderCommand).init(alloc),
        .layout_blocks = ArrayList(GULayoutBlock).init(alloc),
        .render_block = undefined,
        .base_layout = base_layout orelse GULayout{},
        .mouse_pt = .{ .x = -1, .y = -1 },
    });
}

pub fn Deinit(self: *GU) void {
    self.layout_blocks.deinit();
    self.render_commands.deinit();
    self.images.deinit();
    self.fonts.deinit();
}

pub fn BeginFrame(self: *GU) !void {
    std.debug.assert(self.layout_blocks.items.len == 0);
    defer self.render_block = &self.layout_blocks.items[0];

    const surface_size = self.backend.GetSurfaceDimensions();

    self.render_commands.clearRetainingCapacity();
    self.mouse_left.Update();

    self.render_pos = .{ .x = 0, .y = 0 };
    self.render_element = .{ .element = .None, .size = .{ .w = 0, .h = 0 } };
    self.render_override = null;

    try self.layout_blocks.append(.{
        .area = .{ .x = 0, .y = 0, .w = surface_size.w, .h = surface_size.h },
        .layout = self.base_layout,
        .row_elements = 0,
        .row_max_height = 0,
    });
}

pub fn EndFrame(self: *GU) void {
    std.debug.assert(self.layout_blocks.items.len == 1);
    _ = self.layout_blocks.pop();

    for (self.render_commands.items) |command| {
        switch (command) {
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
        }
    }
}

// ELEMENT POSITIONING

// TODO: account for padding, gaps
/// inform system of current element, so that GetNextElementPosition has something
/// to work with
/// calculates how things should be relative to the layout context, and therefore
/// can be used to tell how much space the element will take up in advance
fn SetElementData(self: *GU, element: GUElementType, size: ?GUSize) void {
    if (element == .None) {
        std.debug.assert(size == null);
        self.render_element = GUElementData{ .element = .None, .size = .{ .w = 0, .h = 0 } };
        return;
    }

    const width: f32 = if (self.render_block.layout.widths) |widths| width: {
        const width_def = widths[self.render_block.row_elements % widths.len];

        if (width_def > 0)
            break :width width_def;

        break :width self.render_block.area.w + width_def;
    } else if (element == .LayoutBlock) self.render_block.area.w else size.?.w;

    // TODO: derive height from parent if defined in layout
    const height: f32 = switch (element) {
        .LayoutBlock, .Rect, .Image, .Label, .Button => size.?.h,
        .None => unreachable,
    };

    self.render_element = .{
        .element = element,
        .size = .{ .w = width, .h = height },
    };
}

fn DoNextElementNewLineSetup(self: *GU) void {
    // TODO: pos x: derive from layout state/stack
    // TODO: pos y: use row items max height
    self.render_block.RowMaxHeightIncrement(self.render_element.size.h);
    self.render_pos.x = self.render_block.area.x; // TODO: apply padding
    self.render_pos.y += self.render_block.row_max_height;
    self.render_block.row_max_height = 0;
}

// TODO: track row height (max of element heights on current row) for newline increment
/// resolves a new position for drawing an element, with respect to usage state
/// and layout constraints. state set by functions such as NextElementOverrideX,
/// SetElementData, etc. is 'committed' at this stage and codified into the
/// current (now previous) active element.
fn GetNextElementPosition(self: *GU) GUPos {
    if (self.render_override) |override| {
        return switch (override) {
            .Skip => self.render_pos,
            .NewLine => newline: {
                self.render_block.row_elements = 0;
                self.DoNextElementNewLineSetup();
                self.NextElementOverrideClear();
                break :newline self.render_pos;
            },
            .Position => |pos| pos: {
                // TODO: generalize as a 'free positioning system' and decouple
                // from tracked position, so that you can return to the old
                // positioning state after you're done drawing wherever
                self.render_pos = pos;
                self.NextElementOverrideClear();
                break :pos pos;
            },
            .Offset => |offset| offset: {
                const pos = GUPos{ .x = self.render_pos.x + offset.w, .y = self.render_pos.y + offset.h };
                self.NextElementOverrideClear();
                break :offset pos;
            },
        };
    }

    switch (self.render_element.element) {
        .None => {},
        else => {
            if (self.render_block.layout.widths != null and
                (self.render_block.row_elements + 1) % self.render_block.layout.widths.?.len == 0)
            {
                self.DoNextElementNewLineSetup();
            } else {
                self.render_block.RowMaxHeightIncrement(self.render_element.size.h);
                self.render_pos.x += self.render_element.size.w;
            }
            self.render_block.row_elements += 1;
        },
    }

    return self.render_pos;
}

pub fn NextElementOverrideClear(self: *GU) void {
    std.debug.assert(self.render_override != null);
    self.render_override = null;
}

inline fn NextElementOverrideSet(self: *GU, override: GUPositionOverride) void {
    std.debug.assert(self.render_override == null);
    self.render_override = override;
}

fn NextElementOverrideSkip(self: *GU) void {
    self.NextElementOverrideSet(.{ .Skip = {} });
}

fn NextElementOverrideNewLine(self: *GU) void {
    self.NextElementOverrideSet(.{ .NewLine = {} });
}

pub fn NextElementOverridePosition(self: *GU, pos: GUPos) void {
    self.NextElementOverrideSet(.{ .Position = pos });
}

pub fn NextElementOverrideOffset(self: *GU, offset: GUSize) void {
    self.NextElementOverrideSet(.{ .Offset = offset });
}

// ELEMENTS

pub fn StartLayoutBlock(self: *GU, layout: ?*GULayout) bool {
    const next_pos = self.GetNextElementPosition(); // TODO: apply padding to render_pos after
    const next_size = &self.render_element.size;
    self.SetElementData(.LayoutBlock, .{ .w = 0, .h = 0 });

    self.layout_blocks.append(.{
        .area = .{ .x = next_pos.x, .y = next_pos.y, .w = next_size.w, .h = next_size.h },
        .layout = if (layout) |lo| lo.* else self.base_layout,
        .row_elements = 0,
        .row_max_height = 0,
    }) catch return false;

    self.render_block = &self.layout_blocks.items[self.layout_blocks.items.len - 1];

    self.SetElementData(.None, null);

    return true;
}

pub fn EndLayoutBlock(self: *GU) void {
    const block = self.render_block;
    //if (block.area.h == 0) { // if already set, height was predetermined
    { // TODO: add above condition when implementing preset row heights
        self.NextElementOverrideNewLine();
        const end_pos = self.GetNextElementPosition();
        block.area.h = end_pos.y - block.area.y; // TODO: account for end padding
    }
    self.render_pos = .{ .x = block.area.x, .y = block.area.y };

    _ = self.layout_blocks.pop();
    self.render_block = &self.layout_blocks.items[self.layout_blocks.items.len - 1];

    self.SetElementData(.LayoutBlock, .{ .w = block.area.w, .h = block.area.h });
}

pub const DoNewLine = NextElementOverrideNewLine;

pub fn DoLabel(self: *GU, font: ?usize, color: ?u32, str: []const u8) !void {
    std.debug.assert(self.fonts.items.len >= (font orelse 1));
    const font_ref = &self.fonts.items[font orelse 0];
    try self.render_commands.append(.{
        .Text = .{
            .pos = self.GetNextElementPosition(),
            .font = font_ref,
            .color = color orelse 0xFFFFFFFF,
            .str = str,
        },
    });
    self.SetElementData(.Label, font_ref.StringSize(str));
}

pub fn DoRect(self: *GU, w: f32, h: f32, color: ?u32) !void {
    const pos = self.GetNextElementPosition();
    try self.render_commands.append(.{
        .Rect = .{
            .rect = .{ .x = pos.x, .y = pos.y, .w = w, .h = h },
            .color = color orelse 0xFFFFFFFF,
        },
    });
    self.SetElementData(.Rect, .{ .w = w, .h = h });
}

pub fn DoImage(self: *GU, image: ?usize, color: ?u32) !void {
    std.debug.assert(self.images.items.len >= (image orelse 1));
    const image_ref = &self.images.items[image orelse 0];
    try self.render_commands.append(.{
        .Image = .{
            .pos = self.GetNextElementPosition(),
            .image = &self.images.items[image orelse 0],
            .color = color orelse 0xFFFFFFFF,
            .tile = null,
        },
    });
    self.SetElementData(.Image, image_ref.Size());
}

/// returns whether button was 'activated' (pressed)
pub fn DoButton(self: *GU, btn: *GUButton, font: ?usize, str: []const u8) !bool {
    const pos = self.GetNextElementPosition();

    const f = &self.fonts.items[font orelse 0];
    const str_size = f.StringSize(str);
    const rect = GURect{
        .x = pos.x,
        .y = pos.y,
        .w = GUButton.PADDING_HORIZONTAL * 2 + str_size.w,
        .h = GUButton.PADDING_VERTICAL * 2 + str_size.h,
    };

    const output = btn.Update(&rect, &self.mouse_pt, self.mouse_left.just_down, self.mouse_left.just_up);

    {
        self.NextElementOverrideSkip();
        defer self.NextElementOverrideClear();
        switch (btn.state) {
            .Idle => try self.DoRect(rect.w, rect.h, 0x008000FF),
            .Hover => try self.DoRect(rect.w, rect.h, 0x00C000FF),
            .Down => try self.DoRect(rect.w, rect.h, 0x004000FF),
        }
    }
    self.NextElementOverrideOffset(.{ .w = GUButton.PADDING_HORIZONTAL, .h = GUButton.PADDING_VERTICAL });
    try self.DoLabel(null, null, str);

    self.SetElementData(.Button, .{ .w = rect.w, .h = rect.h });
    return output;
}

// RESOURCES

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
