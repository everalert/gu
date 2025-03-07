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

const GUElement = struct {
    layout: GULayout,
    area: GURect,
    mode: union(enum) {
        None: void,
        Rect: GUSize,
        Image: u32,
        Label: struct {
            font: u32,
            str: []const u8,
        },
    },

    id: usize,
    parent: ?usize,
    children: usize,
    first_child: ?usize,
    sibling_next: ?usize,
    sibling_prev: ?usize,
};

pub const GUElementType = enum(u32) { None, LayoutBlock, Rect, Image, Label, Button };

// intended to pass forward some info to help make layout decisions
pub const GUElementData = struct {
    element: GUElementType,
    size: GUSize,
};

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
        relation: enum { None, Child, Sibling, Parent },
    } {
        if (self.this == null) {
            if (self.source.len == 0) return null;
            self.this = 0;
            self.prev = null;
            return .{ .element = &self.source[0], .relation = .None };
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
    bg: u32,
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

const DEFAULT_LAYOUT = GULayout{ .bg = 0x00000000, .widths = null, .heights = null, .padding = GUSize{ .w = 0, .h = 0 }, .gaps = .{ .w = 0, .h = 0 } };
const BLANK_LAYOUT = GULayout{ .bg = 0x00000000, .widths = null, .heights = null, .padding = GUSize{ .w = 0, .h = 0 }, .gaps = .{ .w = 0, .h = 0 } };

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles
images: ArrayList(GUTextureAtlas), // TODO: impl with handles

element_tree: ArrayList(GUElement),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling

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
    return std.mem.zeroInit(GU, .{
        .allocator = alloc,
        .backend = backend,
        .fonts = ArrayList(GUFontAtlas).init(alloc),
        .images = ArrayList(GUTextureAtlas).init(alloc),
        .element_tree = ArrayList(GUElement).init(alloc),
        .element_stack = ArrayList(usize).init(alloc),
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

// LAYOUT

pub fn BeginFrame(self: *GU) !void {
    std.debug.assert(self.layout_blocks.items.len == 0);
    defer self.render_block = &self.layout_blocks.items[0];

    const surface_size = self.backend.GetSurfaceDimensions();

    std.debug.assert(self.element_stack.items.len == 0);
    self.render_commands.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    self.render_pos = .{ .x = 0, .y = 0 };
    self.render_element = .{ .element = .None, .size = .{ .w = 0, .h = 0 } };
    self.render_override = null;

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

    self.DoElementPositioning();
    self.DoElementDrawCommandEmit();
    //self.DoElementDebugLog();
    for (self.render_commands_new.items) |command| {
        switch (command) {
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
        }
    }
}

// as far as we're concerned, what the user sees as a generic layout container
// is just a 'null' element to us, so we use these internally for clarity
const DoElement = DoContainer;
const EndElement = EndContainer;

/// returns whether creating a new container was successful. guarantees the element
/// tree will be in a valid state (i.e. the same as before calling, on failure).
pub fn DoContainer(self: *GU, layout: ?*const GULayout) bool {
    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const parent: ?*GUElement = if (parent_i) |i| &self.element_tree.items[i] else null;

    const element_i = self.element_tree.items.len; // next index will equal len

    self.element_tree.append(GUElement{
        .area = GURect{ .x = 0, .y = 0, .w = 0, .h = 0 },
        .layout = if (layout) |lo| lo.* else BLANK_LAYOUT,
        .mode = .{ .None = {} },
        .id = element_i,
        .parent = parent_i,
        .sibling_next = null,
        .sibling_prev = self.element_sibling,
        .children = 0,
        .first_child = null,
    }) catch return false;

    self.element_stack.append(element_i) catch {
        _ = self.element_tree.pop();
        return false;
    };

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

    switch (element.mode) {
        .None => {},
        .Rect => |rect| {
            element.area.w = rect.w;
            element.area.h = rect.h;
        },
        .Image => |image_id| {
            const image_size = &self.images.items[image_id].Size();
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
    if (element.children > 1)
        element.area.w += element.layout.gaps.w * @as(f32, @floatFromInt(element.children - 1));

    if (element.parent) |pa_i| {
        const parent = &self.element_tree.items[pa_i];
        parent.area.w += element.area.w;
        parent.area.h = @max(parent.area.h, element.area.h);
    }
}

pub fn SetContainerColor(self: *GU, color: u32) void {
    const i = self.element_stack.getLast();
    const element = &self.element_tree.items[i];
    element.layout.bg = color;
}

pub fn SetContainerPadding(self: *GU, padding: GUSize) void {
    const i = self.element_stack.getLast();
    const element = &self.element_tree.items[i];
    element.layout.padding = padding;
}

fn DoElementPositioning(self: *GU) void {
    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        // first visit only; Child, Sibling and None shouldn't overlap
        if (it_data.relation != .Parent) {
            const base_pos: GUPos, const p_padding: GUSize, const p_gap: GUSize = parenting: {
                if (e.parent) |parent| {
                    const p = &self.element_tree.items[parent];
                    break :parenting .{
                        GUPos{ .x = p.area.x, .y = p.area.y },
                        p.layout.padding,
                        p.layout.gaps,
                    };
                }
                break :parenting .{
                    GUPos{ .x = e.area.x, .y = e.area.y },
                    GUSize{ .w = 0, .h = 0 },
                    GUSize{ .w = 0, .h = 0 },
                };
            };

            if (e.sibling_prev) |sibling_i| {
                const sibling = &self.element_tree.items[sibling_i];
                e.area.x = sibling.area.x + sibling.area.w + p_gap.w;
                e.area.y = sibling.area.y;
                continue;
            }

            if (e.parent) |_| {
                e.area.x = base_pos.x + p_padding.w;
                e.area.y = base_pos.y + p_padding.h;
                continue;
            }
        }
    }
}

fn DoElementDrawCommandEmit(self: *GU) void {
    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        if (it_data.relation == .Parent) continue;
        if (GUColor.FromInt(e.layout.bg).a == 0) continue;
        self.render_commands_new.append(.{
            .Rect = .{
                .rect = .{ .x = e.area.x, .y = e.area.y, .w = e.area.w, .h = e.area.h },
                .color = e.layout.bg,
            },
        }) catch {};
    }
}

fn DoElementDebugLog(self: *GU) void {
    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        std.log.debug(
            "it-element: {s: <10}({*})    {d}x{d}",
            .{ @tagName(it_data.relation), e, e.area.w, e.area.h },
        );
    }
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
