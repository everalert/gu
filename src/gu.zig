const GU = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const maxInt = std.math.maxInt;
const zeroInit = std.mem.zeroInit;

pub const GURect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn PointInRect(self: *const GURect, pt: *const GUPos) bool {
        return pt.x >= self.x and pt.x < self.x + self.w and
            pt.y >= self.y and pt.y < self.y + self.h;
    }

    pub fn Zero() GURect {
        return GURect{ .x = 0, .y = 0, .w = 0, .h = 0 };
    }
};

// TODO: rename to GUPoint?
pub const GUPos = struct {
    x: f32,
    y: f32,

    pub fn FromRect(rect: *GURect) GUPos {
        return GUPos{ .x = rect.x, .y = rect.y };
    }

    pub fn Zero() GUPos {
        return GUPos{ .x = 0, .y = 0 };
    }
};

pub const GUSize = struct {
    w: f32,
    h: f32,

    pub fn FromRect(rect: *GURect) GUSize {
        return GUSize{ .w = rect.w, .h = rect.h };
    }

    pub fn Zero() GUSize {
        return GUSize{ .w = 0, .h = 0 };
    }
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
    area: GURect,
    element: usize,

    pub fn Update(
        self: *GUButton,
        pt: *const GUPos,
        btn_just_down: bool,
        btn_just_up: bool,
    ) bool {
        if (self.area.PointInRect(pt)) {
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

// TODO: impl image tilesets
const GUElement = struct {
    layout: GULayout,
    area: GURect,
    mode: union(enum) {
        Block: void,
        Rect: GUSize,
        Image: struct {
            image: GUImageHandle,
            //tile: ?u32,
        },
        Label: struct {
            str: []const u8,
            font: GUFontHandle,
        },
        Button: void,
    },

    id: usize,
    parent: ?usize,
    children: usize,
    first_child: ?usize,
    sibling_next: ?usize,
    sibling_prev: ?usize,
    line_break: bool,
};

pub const GUElementType = enum(u32) { None, LayoutBlock, Rect, Image, Label, Button };

// intended to pass forward some info to help make layout decisions
pub const GUElementData = struct {
    element: GUElementType,
    size: GUSize,
};

// FIXME: iterator won't traverse the whole element list if there are multiple top
// level nodes
// TODO: specify traversal order during Init, as a convenience so that user doesn't
// have to manually skip items when it's order-based
/// depth-first walk of element tree with pre- and post-order traversal; elements
/// with children are touched both on the way down and up, i.e. once before then
/// again after any children are walked
const GUElementIterator = struct {
    source: []GUElement,
    this: ?usize,
    prev: ?usize,

    pub fn Init(source: []GUElement) GUElementIterator {
        return GUElementIterator{
            .source = source,
            .this = null,
            .prev = null,
        };
    }

    pub fn Next(self: *GUElementIterator) ?struct {
        element: *GUElement,
        relation: enum { Root, Child, Sibling, Parent },
    } {
        if (self.this == null) {
            if (self.source.len == 0) return null;
            self.this = 0;
            self.prev = null;
            return .{ .element = &self.source[0], .relation = .Root };
        }

        const p = self.prev;
        const t = self.this.?;
        const element = self.source[self.this.?];

        self.prev = self.this;

        // only go to child if last movement not child-to-parent
        if ((p == null or p.? < t) and element.first_child != null) {
            self.this = element.first_child.?;
            return .{
                .element = &self.source[element.first_child.?],
                .relation = .Child,
            };
        }

        if (element.sibling_next) |sibling| {
            self.this = sibling;
            return .{
                .element = &self.source[sibling],
                .relation = .Sibling,
            };
        }

        if (element.parent) |parent| {
            self.this = parent;
            return .{
                .element = &self.source[parent],
                .relation = .Parent,
            };
        }

        return null;
    }
};

pub const GULayout = struct {
    color: u32,
    widths: ?[]const f32,
    heights: ?[]const f32,
    padding: GUSize,
    gaps: GUSize,
    //scroll: ?
};

pub const GULayoutBlock = struct {
    area: GURect,
    layout: GULayout,
    row_number: u32,
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

const GULineData = struct {
    parent_padding: GUSize,
    parent_gaps: GUSize,
    line: u32,
    current_y: f32,
    current_h: f32,
    current_items: u32,
    current_w: f32,
    max_w: f32, // incl padding/gaps
};

const GUImageHandle = usize;
const GUFontHandle = usize;

const DEFAULT_LAYOUT = GULayout{ .color = 0x00000000, .widths = null, .heights = null, .padding = GUSize.Zero(), .gaps = GUSize.Zero() };
const BLANK_LAYOUT = GULayout{ .color = 0x00000000, .widths = null, .heights = null, .padding = GUSize.Zero(), .gaps = GUSize.Zero() };

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles, update GUFontHandle
images: ArrayList(GUTextureAtlas), // TODO: impl with handles, update GUImageHandle

element_tree: ArrayList(GUElement),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling
element_queue_line_break: bool,
element_line_stack: ArrayList(GULineData),

buttons: StringHashMap(GUButton),
button_delete_queue: ArrayList([]const u8),

layout_blocks: ArrayList(GULayoutBlock), // FIXME: deprecated
base_layout: GULayout,

render_commands_new: ArrayList(GURenderCommand), // FIXME: for refactor, delete and rename/remove refs when finalizing
render_commands: ArrayList(GURenderCommand),
render_pos: GUPos, // FIXME: deprecated
render_block: *GULayoutBlock, // FIXME: deprecated
render_element: GUElementData, // FIXME: deprecated
render_override: ?GUPositionOverride, // FIXME: deprecated

mouse_pt: GUPos,
mouse_left: GUButtonState, // LMB

pub fn Init(alloc: Allocator, backend: GUBackend, base_layout: ?GULayout) GU {
    return zeroInit(GU, .{
        .allocator = alloc,
        .backend = backend,
        .fonts = ArrayList(GUFontAtlas).init(alloc),
        .images = ArrayList(GUTextureAtlas).init(alloc),
        .element_tree = ArrayList(GUElement).init(alloc),
        .element_stack = ArrayList(usize).init(alloc),
        .element_line_stack = ArrayList(GULineData).init(alloc),
        .buttons = StringHashMap(GUButton).init(alloc),
        .button_delete_queue = ArrayList([]const u8).init(alloc),
        .render_commands_new = ArrayList(GURenderCommand).init(alloc),
        .render_commands = ArrayList(GURenderCommand).init(alloc),
        .layout_blocks = ArrayList(GULayoutBlock).init(alloc),
        .render_block = undefined,
        .base_layout = base_layout orelse DEFAULT_LAYOUT,
        .mouse_pt = .{ .x = -1, .y = -1 },
    });
}

pub fn Deinit(self: *GU) void {
    self.layout_blocks.deinit();
    self.render_commands_new.deinit();
    self.render_commands.deinit();
    self.element_line_stack.deinit();
    self.element_stack.deinit();
    self.element_tree.deinit();
    self.images.deinit();
    self.fonts.deinit();
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

// FRAME

pub fn BeginFrame(self: *GU) !void {
    const surface_size = self.backend.GetSurfaceDimensions();

    std.debug.assert(self.element_stack.items.len == 0);
    std.debug.assert(self.element_line_stack.items.len == 0);
    self.render_commands.clearRetainingCapacity();
    self.render_commands_new.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    // TODO: set fixed size with dimensions matching window
    if (!self.DoElement(&self.base_layout)) unreachable;

    // FIXME: delete all below, only relevant to old impl
    self.render_pos = GUPos.Zero();
    self.render_element = .{ .element = .None, .size = GUSize.Zero() };
    self.render_override = null;

    std.debug.assert(self.layout_blocks.items.len == 0);
    defer self.render_block = &self.layout_blocks.items[0];

    try self.layout_blocks.append(.{
        .area = .{ .x = 0, .y = 0, .w = surface_size.w, .h = surface_size.h },
        .layout = self.base_layout,
        .row_number = 0,
        .row_elements = 0,
        .row_max_height = 0,
    });
    self.render_block = &self.layout_blocks.items[self.layout_blocks.items.len - 1];

    self.render_pos.x += self.render_block.layout.padding.w;
    self.render_pos.y += self.render_block.layout.padding.h;
}

// TODO: initial element sizing as an explicit pass separate from the initial
// element tree generation?
pub fn EndFrame(self: *GU) void {
    // old stuff
    std.debug.assert(self.layout_blocks.items.len == 1);
    _ = self.layout_blocks.pop();
    for (self.render_commands.items) |command| {
        switch (command) {
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
        }
    }

    // new stuff
    self.EndElement(); // close base layout container
    self.DoElementLineBreakParsing();
    self.DoElementPositioning();
    self.DoButtonPostProcessing();
    self.DoElementEmitDrawCommands();
    //self.DoElementDebugLog();

    for (self.render_commands_new.items) |command| {
        switch (command) {
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
        }
    }
}

// TODO: update when implementing fixed-size dimensions, i.e. line break when
// exceeding width and don't update fixed dimensions
// TODO: update for text wrapping
/// inserts line break markers where needed, and updates parent dimensions in
/// case of line breaks occurring
fn DoElementLineBreakParsing(self: *GU) void {
    std.debug.assert(self.element_line_stack.items.len == 0);
    defer std.debug.assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(GULineData, .{ .line = 1 });
    var ld: *GULineData = &ld_base;

    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (it_data.relation == .Parent) {
            e.area.w = @max(ld.max_w, ld.current_w + ld.parent_padding.w * 2 + ld.parent_gaps.w * @as(f32, @floatFromInt(ld.current_items -| 1)));
            e.area.h = ld.current_h + ld.current_y + ld.parent_padding.h * 2 + ld.parent_gaps.h * @as(f32, @floatFromInt(ld.line -| 1));
            _ = self.element_line_stack.pop();
            ld = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &ld_base;
            ld.current_items += 1;
            ld.current_w += e.area.w;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        if (it_data.relation == .Child) {
            const p = &self.element_tree.items[e.parent.?];
            stack.append(zeroInit(GULineData, .{
                .parent_padding = p.layout.padding,
                .parent_gaps = p.layout.gaps,
            })) catch |err| std.debug.panic("DoElementLineBreakParsing ({s})", .{@errorName(err)});
            ld = &stack.items[stack.items.len - 1];
        }

        // .Root init covered by ld_base
        if (it_data.relation == .Child or e.line_break) {
            ld.max_w = @max(ld.max_w, ld.current_w + ld.parent_padding.w * 2 + ld.parent_gaps.w * @as(f32, @floatFromInt(ld.current_items -| 1)));
            ld.line += 1;
            ld.current_y += ld.current_h;
            ld.current_w = 0;
            ld.current_h = 0;
            ld.current_items = 0;
        }

        // do the following when returning as parent, to prevent propagating
        // pre-resized dimensions
        if (e.first_child != null) continue;
        ld.current_items += 1;
        ld.current_w += e.area.w;
        ld.current_h = @max(ld.current_h, e.area.h);
    }
}

fn DoElementPositioning(self: *GU) void {
    std.debug.assert(self.element_line_stack.items.len == 0);
    defer std.debug.assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(GULineData, .{});
    var ld: *GULineData = &ld_base;
    var p: ?*GUElement = null;

    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (it_data.relation == .Parent) {
            _ = self.element_line_stack.pop();
            ld = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &ld_base;
            p = if (e.parent) |parent| &self.element_tree.items[parent] else null;
            continue;
        }

        if (it_data.relation == .Child) {
            p = &self.element_tree.items[e.parent.?];
            stack.appendAssumeCapacity(zeroInit(GULineData, .{})); // capacity set during linebreak parsing
            ld = &stack.items[stack.items.len - 1];
            e.area.x = p.?.area.x + p.?.layout.padding.w;
            e.area.y = p.?.area.y + p.?.layout.padding.h;
            ld.current_y = e.area.y;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        const gaps = if (p != null) p.?.layout.gaps else GUSize.Zero();

        if (e.line_break) {
            const pos = if (p != null) GUPos.FromRect(&p.?.area) else GUPos.Zero();
            const padding = if (p != null) p.?.layout.padding else GUSize.Zero();
            e.area.x = pos.x + padding.w;
            e.area.y = ld.current_y + ld.current_h + gaps.h;
            ld.current_y = e.area.y;
            ld.current_h = e.area.h;
        } else {
            const area = if (e.sibling_prev) |s| self.element_tree.items[s].area else GURect.Zero();
            e.area.x = area.x + area.w + gaps.w;
            e.area.y = ld.current_y;
            ld.current_h = @max(ld.current_h, e.area.h);
        }
    }
}

// FIXME: probably don't need an iterator here, since the element tree should be
// implicitly in the correct order with respect to z-order when read linearly
fn DoElementEmitDrawCommands(self: *GU) void {
    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        if (it_data.relation == .Parent) continue;
        const e = it_data.element;

        if (GUColor.FromInt(e.layout.color).a == 0) continue;

        self.render_commands_new.append(switch (e.mode) {
            .Label => |label| .{ .Text = .{
                .pos = .{ .x = e.area.x, .y = e.area.y },
                .font = &self.fonts.items[label.font],
                .color = e.layout.color,
                .str = label.str,
            } },
            .Image => |img| .{ .Image = .{
                .pos = .{ .x = e.area.x, .y = e.area.y },
                .image = &self.images.items[img.image],
                .color = e.layout.color,
                .tile = null,
            } },
            .Rect, .Button, .Block => .{ .Rect = .{
                .rect = .{ .x = e.area.x, .y = e.area.y, .w = e.area.w, .h = e.area.h },
                .color = e.layout.color,
            } },
        }) catch |err| std.log.err("DoElementEmitDrawCommands ({s})", .{@errorName(err)});
    }
}

fn DoElementDebugLog(self: *GU) void {
    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        std.log.debug(
            "it-element: ({*})  {s: <12}{s: <10}{d}x{d}",
            .{ e, @tagName(it_data.relation), @tagName(e.mode), e.area.w, e.area.h },
        );
    }
}

fn DoButtonPostProcessing(self: *GU) void {
    std.debug.assert(self.button_delete_queue.items.len == 0);

    var it = self.buttons.iterator();
    while (it.next()) |btn_info| {
        const btn = btn_info.value_ptr;
        if (btn.element == maxInt(usize)) {
            self.button_delete_queue.append(btn_info.key_ptr.*) catch |err|
                std.debug.panic("DoButtonPostProcessing ({s})", .{@errorName(err)});
            continue;
        }
        btn.area = self.element_tree.items[btn.element].area;
        btn.element = maxInt(usize);
    }

    while (self.button_delete_queue.popOrNull()) |item|
        _ = self.buttons.remove(item);
}

// LAYOUT

/// returns whether creating a new container was successful. guarantees the element
/// tree will be in a valid state (i.e. the same as before calling, on failure).
pub fn DoContainer(self: *GU, layout: ?*const GULayout) bool {
    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const element_i = self.element_tree.items.len; // next index will equal len

    const do_line_break: bool = lb: {
        if (!self.element_queue_line_break) break :lb false;
        self.element_queue_line_break = false;
        break :lb true;
    };

    self.element_tree.append(GUElement{
        .area = GURect.Zero(),
        .layout = if (layout) |lo| lo.* else BLANK_LAYOUT,
        .mode = .{ .Block = {} },
        .id = element_i,
        .parent = parent_i,
        .sibling_next = null,
        .sibling_prev = self.element_sibling,
        .children = 0,
        .first_child = null,
        .line_break = do_line_break,
    }) catch return false;

    self.element_stack.append(element_i) catch {
        _ = self.element_tree.pop();
        return false;
    };

    const parent: ?*GUElement = if (parent_i) |i| &self.element_tree.items[i] else null;

    if (parent) |pa| {
        if (pa.first_child == null) pa.first_child = element_i;
        pa.children += 1;
    }

    if (self.element_sibling) |sibling| {
        self.element_tree.items[sibling].sibling_next = element_i;
        self.element_sibling = null;
    }

    return true;
}

pub fn EndContainer(self: *GU) void {
    const element_i = self.element_stack.pop();
    const element = &self.element_tree.items[element_i];
    self.element_sibling = element_i;
    self.element_queue_line_break = false; // cleanup unused line break

    switch (element.mode) {
        .Block, .Button => {},
        .Rect => |rect| {
            element.area.w = rect.w;
            element.area.h = rect.h;
        },
        .Image => |image| {
            const image_size = &self.images.items[image.image].Size();
            element.area.w = image_size.w;
            element.area.h = image_size.h;
        },
        .Label => |label| {
            const label_size = &self.fonts.items[label.font].StringSize(label.str);
            element.area.w = label_size.w;
            element.area.h = label_size.h;
        },
    }

    element.area.w += element.layout.padding.w * 2;
    element.area.h += element.layout.padding.h * 2;
    element.area.w += element.layout.gaps.w * @as(f32, @floatFromInt(element.children -| 1));

    if (element.parent) |pa_i| {
        const parent = &self.element_tree.items[pa_i];
        parent.area.w += element.area.w;
        parent.area.h = @max(parent.area.h, element.area.h);
    }
}

pub inline fn GetContainer(self: *GU) *GUElement {
    const i = self.element_stack.getLast();
    const element = &self.element_tree.items[i];
    return element;
}

pub fn SetContainerColor(self: *GU, color: u32) void {
    const element = self.GetContainer();
    element.layout.color = color;
}

pub fn SetContainerPadding(self: *GU, padding: GUSize) void {
    const element = self.GetContainer();
    element.layout.padding = padding;
}

pub fn SetContainerGaps(self: *GU, gaps: GUSize) void {
    const element = self.GetContainer();
    element.layout.gaps = gaps;
}

pub fn SetContainerSize(self: *GU, w: f32, h: f32) void {
    const element = self.GetContainer();
    element.area.w = w;
    element.area.h = h;
}

// as far as we're concerned, what the user sees as a generic layout container
// is just a 'null' element to us, so we use these internally for clarity
const DoElement = DoContainer;
const EndElement = EndContainer;
const GetElement = GetContainer;
const SetElementPadding = SetContainerPadding;
const SetElementGaps = SetContainerGaps;
const SetElementColor = SetContainerColor;
const SetElementSize = SetContainerSize;

// FIXME: rename at refactor handover
pub fn DoRectNEW(self: *GU, size: GUSize, color: u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Rect = size };
    element.layout.color = color;
}

// FIXME: rename at refactor handover
pub fn DoImageNEW(self: *GU, image: GUImageHandle, color: ?u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Image = .{ .image = image } };
    element.layout.color = color orelse 0xFFFFFFFF;
}

// TODO: add formatting, like standard string formatting functions
// FIXME: rename at refactor handover
pub fn DoLabelNEW(self: *GU, font: ?GUFontHandle, color: ?u32, str: []const u8) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Label = .{ .font = font orelse 0, .str = str } };
    element.layout.color = color orelse 0xFFFFFFFF;
}

/// returns whether button was 'activated' (pressed)
pub fn DoButtonNEW(self: *GU, font: ?usize, str: []const u8) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Button = {} };

    const btn: *GUButton = get_button: {
        const btn_key = std.fmt.allocPrint(self.allocator, "{X:0>16}{s}", .{ element.id, str }) catch
            return false;
        const btn_info = self.buttons.getOrPut(btn_key) catch
            return false;

        const btn = btn_info.value_ptr;
        if (!btn_info.found_existing) {
            btn.* = GUButton{
                .state = .Idle,
                .mode = .Press,
                .area = GURect.Zero(),
                .element = element.id,
            };
        } else btn.element = element.id;

        break :get_button btn;
    };

    const activated = btn.Update(
        &self.mouse_pt,
        self.mouse_left.just_down,
        self.mouse_left.just_up,
    );

    element.layout.color = switch (btn.state) {
        .Idle => 0x008000FF,
        .Hover => 0x00C000FF,
        .Down => 0x004000FF,
    };
    element.layout.padding = .{ .w = GUButton.PADDING_HORIZONTAL, .h = GUButton.PADDING_VERTICAL };

    self.DoLabelNEW(font, null, str);

    return activated;
}

pub fn DoLineBreak(self: *GU) void {
    self.element_queue_line_break = true;
}

// ------------------
// WARNING: OLD STUFF
// ------------------

// ELEMENT POSITIONING

// TODO: minimum length for dynamic case
inline fn ResolveElementDimension(values: ?[]const f32, index: u32, parent_size: f32, default: f32) f32 {
    if (values == null) return default;

    const def = values.?[index % values.?.len];
    if (def > 0) return def;
    return parent_size + def; // in dynamic case, size is negated from scope size
}

// TODO: account for gaps
/// inform system of current element, so that GetNextElementPosition has something
/// to work with. calculates how things should be relative to the layout context,
/// and therefore can be used to tell how much space the element will take up in
/// advance for trivial element sizing cases
fn SetElementData(self: *GU, element: GUElementType, size: ?GUSize) void {
    if (element == .None) {
        std.debug.assert(size == null);
        self.render_element = GUElementData{ .element = .None, .size = .{ .w = 0, .h = 0 } };
        return;
    }

    const padding: GUSize = self.render_block.layout.padding;

    // TODO: change LayoutBlock width to equal max row size, just like height; will
    // need to solve same problem height has with resolving child dimension in the
    // interim before the final dimension can be known
    const width = ResolveElementDimension(
        self.render_block.layout.widths,
        self.render_block.row_elements,
        self.render_block.area.w - padding.w * 2,
        if (element == .LayoutBlock) self.render_block.area.w else size.?.w,
    );

    // FIXME: because dynamically sized layout blocks are sized at 0 in the interim
    // as a way of signaling a later resize, dynamic defined row sizes (negative
    // number) resolve to a negative height, fucking all of it up. one idea to
    // resolve this may be to implement a deferred sizing queue that keeps track
    // of what needs to be resized and what depends on it, then clear that at
    // the end of each layout scope to make sure there is no bleed or excessive
    // dependency chain
    const height = ResolveElementDimension(
        self.render_block.layout.heights,
        self.render_block.row_number,
        self.render_block.area.h - padding.h * 2,
        size.?.h,
    );

    self.render_element = .{
        .element = element,
        .size = .{ .w = width, .h = height },
    };
}

fn DoNextElementNewLineSetup(self: *GU) void {
    // TODO: pos x: derive from layout state/stack
    // TODO: pos y: use row items max height
    const padding = self.render_block.layout.padding;
    self.render_block.RowMaxHeightIncrement(self.render_element.size.h);
    self.render_pos.x = self.render_block.area.x + padding.w;
    self.render_pos.y += self.render_block.row_max_height;
    self.render_block.row_max_height = 0;
    self.render_block.row_number += 1;
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

pub fn StartLayoutBlock(self: *GU, layout: ?*const GULayout) bool {
    const next_pos = self.GetNextElementPosition();
    const next_size = &self.render_element.size;
    self.SetElementData(.LayoutBlock, .{ .w = 0, .h = 0 }); // filled in by SetElementData if able

    self.layout_blocks.append(.{
        .area = .{ .x = next_pos.x, .y = next_pos.y, .w = next_size.w, .h = next_size.h },
        .layout = if (layout) |lo| lo.* else BLANK_LAYOUT,
        .row_number = 0,
        .row_elements = 0,
        .row_max_height = 0,
    }) catch return false;

    self.render_block = &self.layout_blocks.items[self.layout_blocks.items.len - 1];
    self.render_pos.x += self.render_block.layout.padding.w;
    self.render_pos.y += self.render_block.layout.padding.h;

    self.SetElementData(.None, null);

    return true;
}

pub fn EndLayoutBlock(self: *GU) void {
    const block = self.render_block;
    if (block.area.h == 0) { // if already set, height was predetermined
        const padding = self.render_block.layout.padding;
        self.NextElementOverrideNewLine();
        const end_pos = self.GetNextElementPosition();
        block.area.h = end_pos.y - block.area.y - padding.h * 2;
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
