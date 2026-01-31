const GU = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const FormatOptions = std.fmt.FormatOptions;
const maxInt = std.math.maxInt;
const zeroInit = std.mem.zeroInit;

const Vec2 = @import("m_vec2.zig");
const Rect = @import("m_rect.zig");
const Color = @import("m_color.zig").Color;

pub const GUBackend = struct {
    ptr: *anyopaque,
    fnGetSurfaceDimensions: *const fn (*anyopaque) Vec2,
    fnDrawRect: *const fn (*anyopaque, *const RCRect) void,
    fnDrawString: *const fn (*anyopaque, *const RCText) void,
    fnSetClip: *const fn (*anyopaque, *const RCClip) void,
    fnBeginRendering: *const fn (*anyopaque) void,
    fnEndRendering: *const fn (*anyopaque) void,

    pub fn GetSurfaceDimensions(self: *GUBackend) Vec2 {
        return self.fnGetSurfaceDimensions(self.ptr);
    }

    // TODO: impl texture tile drawing, see GURenderCommand->Rect
    pub fn DrawRect(self: *GUBackend, cmd: *const RCRect) void {
        self.fnDrawRect(self.ptr, cmd);
    }

    pub fn DrawString(self: *GUBackend, cmd: *const RCText) void {
        self.fnDrawString(self.ptr, cmd);
    }

    pub fn SetClip(self: *GUBackend, cmd: *const RCClip) void {
        self.fnSetClip(self.ptr, cmd);
    }

    /// called as a way to signal to the backend that we are about to render a
    /// frame, and give it a 'hook' to do any related setup (store clip state, etc.)
    pub fn BeginRendering(self: *GUBackend) void {
        self.fnBeginRendering(self.ptr);
    }

    /// a 'hook' for the backend to cleanup after we're done with a frame
    pub fn EndRendering(self: *GUBackend) void {
        self.fnEndRendering(self.ptr);
    }
};

//------------------------------------------------------------------------------

// FIXME: don't really like having the field types separated, but afaik needed to
// pass their types to function params (see GUBackend); investigate to confirm
// that it's actually not possible/practical to reference the field type directly
// WARN: also, not sure it's necessarily a good idea to obfuscate the field members
// when calling the GUBackend functions; however, it makes for cleaner fn defs
// and theoretically cuts down on stack thrashing (to compare/confirm), need to
// make a final call on which way to do it
pub const RenderCommand = struct {
    kind: Kind,
    handle: usize, // TODO: actual handle impl

    pub const Kind = enum { rect, text, clip };

    pub fn init(kind: Kind, handle: usize) RenderCommand {
        return .{ .handle = handle, .kind = kind };
    }
};

pub const RCRect = struct {
    rect: Rect,
    corner: Corner,
    color: u32,
    texture: ?*GUTextureAtlas,
    tile: ?u32, // for texture atlases

    pub fn init(rect: Rect, corner: Corner, color: u32) RCRect {
        return std.mem.zeroInit(RCRect, .{
            .rect = rect,
            .corner = corner,
            .color = color,
        });
    }
};

pub const RCText = struct {
    str: []const u8,
    font: *GUFontAtlas,
    pos: Vec2,
    color: u32,
};

pub const RCClip = struct {
    area: Rect,
};

pub const Corner = struct {
    radius: f32,
    style: CornerShape,
};

// FIXME: does this even need to be an enum, rather than like an id or handle?
//  the backend has to decide what to implement anyway, so..
pub const CornerShape = enum { None, Round, Custom1, Custom2, Custom3, Custom4, Custom5, Custom6 };

//------------------------------------------------------------------------------

pub const FontHandle = usize;
pub const TextureHandle = usize;

// FIXME: not sure this needs to be in ui core, maybe adding these to backend
//  vtable is enough? so we only remember handles (provided by backend)
// TODO: add CanDrawString to check against supported character range in font impl
pub const GUFontAtlas = struct {
    ptr: *anyopaque,
    fnDrawString: *const fn (*anyopaque, []const u8, *const Vec2) void,
    fnDrawChar: *const fn (*anyopaque, u8, *const Vec2) void,
    fnStringSize: *const fn (*anyopaque, []const u8) Vec2,
    fnCharSize: *const fn (*anyopaque, u8) Vec2,
    fnSetColor: *const fn (*anyopaque, u32) void,

    pub fn DrawString(self: *GUFontAtlas, str: []const u8, pos: *const Vec2) void {
        self.fnDrawString(self.ptr, str, pos);
    }

    pub fn DrawChar(self: *GUFontAtlas, char: u8, pos: *const Vec2) void {
        self.fnDrawChar(self.ptr, char, pos);
    }

    pub fn StringSize(self: *GUFontAtlas, str: []const u8) Vec2 {
        return self.fnStringSize(self.ptr, str);
    }

    pub fn CharSize(self: *GUFontAtlas, char: u8) Vec2 {
        return self.fnCharSize(self.ptr, char);
    }

    pub fn SetColor(self: *GUFontAtlas, color: u32) void {
        return self.fnSetColor(self.ptr, color);
    }
};

// TODO: tiling; i.e. actually make it an atlas
// FIXME: not sure this needs to be in ui core, maybe adding these to backend
//  vtable is enough? so we only remember handles (provided by backend)
pub const GUTextureAtlas = struct {
    ptr: *anyopaque,
    fnDraw: *const fn (*anyopaque, *const Vec2) void,
    fnSize: *const fn (*anyopaque) Vec2,
    fnSetColor: *const fn (*anyopaque, u32) void,

    pub fn Draw(self: *GUTextureAtlas, pos: *const Vec2) void {
        self.fnDraw(self.ptr, pos);
    }

    pub fn Size(self: *GUTextureAtlas) Vec2 {
        return self.fnSize(self.ptr);
    }

    pub fn SetColor(self: *GUTextureAtlas, color: u32) void {
        return self.fnSetColor(self.ptr, color);
    }
};

//------------------------------------------------------------------------------

pub const Button = struct {
    mode: ButtonMode = .Press,
    state: ButtonState = .Idle,
    area: Rect,
    element: usize,
    activated: bool,

    pub const empty = Button{
        .mode = .default,
        .state = .Idle,
        .area = .zero,
        .element = maxInt(usize), // FIXME: probably bad that this refers to oob, no?
        .activated = false,
    };

    pub fn Update(
        self: *Button,
        pt: *const Vec2,
        btn_just_down: bool,
        btn_just_up: bool,
    ) void {
        self.activated = false;
        if (self.area.IsCollidingPoint(pt)) {
            if (self.state == .Idle)
                self.state = .Hover;

            if (self.state == .Hover and btn_just_down) {
                self.state = .Down;
                if (self.mode == .Press) {
                    std.log.debug("button activated! (press)", .{});
                    self.activated = true;
                    return;
                }
            }

            if (self.state == .Down and btn_just_up) {
                self.state = .Hover;
                if (self.mode == .Release) {
                    std.log.debug("button activated! (release)", .{});
                    self.activated = true;
                    return;
                }
            }
        } else {
            self.state = .Idle;
        }
    }
};

pub const ButtonMode = enum {
    Press,
    Release,

    pub const default: ButtonMode = .Press;
};

pub const ButtonState = enum { Idle, Hover, Down };

pub const ButtonStyle = struct {
    PaddingVer: f32,
    PaddingHor: f32,
    CornerRad: f32,
    CornerShape: CornerShape,
    ColorIdle: u32,
    ColorHover: u32,
    ColorDown: u32,

    const default: ButtonStyle = .{
        .PaddingVer = 2,
        .PaddingHor = 8,
        .CornerRad = 6,
        .CornerShape = .Round,
        .ColorIdle = 0x008000FF,
        .ColorHover = 0x00C000FF,
        .ColorDown = 0x004000FF,
    };
};

pub const KeyState = struct {
    down: bool = false,
    just_up: bool = false,
    just_down: bool = false,
    accumulator_down: bool = false,
    accumulator_changes: u32 = 0,

    pub const default = zeroInit(KeyState, .{});

    pub fn Accumulate(self: *KeyState, down: bool) void {
        if (self.accumulator_down != down) {
            self.accumulator_down = down;
            self.accumulator_changes += 1;
        }
    }

    pub fn Update(self: *KeyState) void {
        self.just_down = (self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.just_up = (!self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.down = self.accumulator_down;
        self.accumulator_changes = 0;
    }
};

//------------------------------------------------------------------------------

// TODO: impl texture tilesets
// TODO: impl absolute/relative positioning
const Element = struct {
    id: usize,
    parent: ?usize,
    children: usize,
    first_child: ?usize,
    sibling_next: ?usize,
    sibling_prev: ?usize,

    features: Features,
    layout: GULayout,
    area: Rect,
    fill: Vec2, // how big the element is for layout calculations
    texture: TextureHandle,
    name: []const u8,
    label_str: []const u8,
    label_font: FontHandle,
    rect_size: Vec2,

    const empty: Element = .{
        .layout = .default,
        .area = .zero,
        .fill = .zero,
        .id = 0,
        .parent = null,
        .children = 0,
        .first_child = null,
        .sibling_next = null,
        .sibling_prev = null,
        .features = .none,
        .texture = maxInt(usize),
        .name = &.{},
        .label_str = &.{},
        .label_font = maxInt(usize),
        .rect_size = .zero,
    };

    // TODO: ?? rename bShowRect -> bShowBody or bShowBackground
    // TODO: body shadow
    // TODO: body outline
    // TODO: texture tiling
    // TODO: texture scaling
    // TODO: texture stretch to rect size
    // TODO: texture treated as 9grid
    // TODO: text wrapping
    // TODO: text shadow
    // TODO: text outline
    // TODO: text wrapping (dynamic multiline text)
    // TODO: button uses visual button styling (or is left unstyled)
    // TODO: enable clipping (i.e. "allow/disallow visual overflow")
    const Features = packed struct(u32) {
        // Visual functionality
        bShowRect: bool, // render the body of the element
        bShowTexture: bool, // use a texture on the element body
        bShowLabel: bool,

        // Layout functionality
        bLineBreak: bool,

        // Button functionality
        bClickable: bool,
        bClickDown: bool,
        bClickHover: bool,
        bClickDepressed: bool, // button visually "idles" in down-state

        _: u24,

        const none: Features = @bitCast(@as(u32, 0));
        const all: Features = @bitCast(maxInt(u32));
    };
};

// TODO: specify traversal order during Init, as a convenience so that user doesn't
// have to manually skip items when it's order-based
/// depth-first walk of element tree with pre- and post-order traversal; elements
/// with children are touched both on the way down and up, i.e. once before then
/// again after any children are walked
const ElementIterator = struct {
    source: []Element,
    this: ?usize,
    prev: ?usize,

    pub fn Init(source: []Element) ElementIterator {
        return ElementIterator{
            .source = source,
            .this = null,
            .prev = null,
        };
    }

    pub fn Next(self: *ElementIterator) ?struct {
        element: *Element,
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

//------------------------------------------------------------------------------

pub const GULayout = struct {
    mode_w: GUDimensionMode, // derived from parent 'widths' field if .Auto
    mode_h: GUDimensionMode, // derived from parent 'heights' field if .Auto
    color: u32,
    corner: Corner,
    widths: ?[]const f32, // FIXME: doesn't need to be null
    heights: ?[]const f32, // FIXME: doesn't need to be null
    padding: Vec2,
    gaps: Vec2,
    auto_line_break: bool,
    //scroll: ?

    const default = zeroInit(GULayout, .{
        .auto_line_break = true,
    });
};

const GULineData = struct {
    parent_padding: Vec2,
    parent_gaps: Vec2,
    line: u32,
    current_y: f32,
    current_h: f32,
    current_items: u32,
    current_w: f32,
    max_w: f32, // incl padding/gaps

    // TODO: impl axis def in GULayout and derive
    pub inline fn AxisSpacing(self: *GULineData, comptime axis: enum { Main, Cross }, items: usize) f32 {
        const padding: f32, const gaps: f32 = switch (axis) {
            .Main => .{ // x-axis
                self.parent_padding.x * 2,
                self.parent_gaps.x * @as(f32, @floatFromInt(items -| 1)),
            },
            .Cross => .{ // y-axis
                self.parent_padding.y * 2,
                self.parent_gaps.y * @as(f32, @floatFromInt(items -| 1)),
            },
        };
        return padding + gaps;
    }
};

// FIXME: Auto and Fit are not actually referenced anywhere??? so basically it's
//  assumed an element is Auto(Fit) if a dimension is not Stretch or Fixed, without
//  actually checking???
const GUDimensionMode = enum {
    /// Select one of the other modes based on input/context; see `ParseAuto`.
    Auto,
    /// Reduce to child dimensions plus any margins, etc.
    Fit,
    /// Expand to usable space of parent dimension minus input value; requires
    /// pre-finalizable parent dimension.
    Stretch,
    /// Size is pre-determined and not subject to manipulation.
    Fixed,

    // FIXME: similarly, this function gets used pathologically with the assumption
    //  that the element is Auto, without checking
    fn ParseAuto(dimension: f32) GUDimensionMode {
        const sign = std.math.sign(dimension);
        if (sign == 1) return .Fixed;
        if (sign == 0) return .Fit;
        if (sign == -1) return .Stretch;
        unreachable;
    }

    /// Whether the dimension can be finalized before evaluating the size of any
    /// child elements.
    inline fn IsPreComputable(mode: GUDimensionMode) bool {
        return mode == .Fixed or mode == .Stretch;
    }
};

//------------------------------------------------------------------------------

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles, update GUFontHandle
textures: ArrayList(GUTextureAtlas), // TODO: impl with handles, update GUTextureHandle

element_tree: ArrayList(Element),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling
element_queue_line_break: bool,
element_line_stack: ArrayList(GULineData),

clip_stack: ArrayList(Rect),
label_arena: ArenaAllocator,

base_layout: GULayout,

buttons: StringHashMap(Button),
button_delete_queue: ArrayList([]const u8),
btn_mode_stack: ArrayList(ButtonMode),

btn_style_arena: ArrayList(ButtonStyle), // arraylist for the typing/alignment, usage is like arena
btn_style_stack_padding_ver: ArrayList(f32),
btn_style_stack_padding_hor: ArrayList(f32),
btn_style_stack_corner_rad: ArrayList(f32),
btn_style_stack_corner_shape: ArrayList(CornerShape),
btn_style_stack_color_idle: ArrayList(u32),
btn_style_stack_color_hover: ArrayList(u32),
btn_style_stack_color_down: ArrayList(u32),
btn_style_stack_changed: bool,

render_commands: ArrayList(RenderCommand),
render_commands_rect: ArrayList(RCRect),
render_commands_text: ArrayList(RCText),
render_commands_clip: ArrayList(RCClip),

mouse_pt: Vec2,
mouse_left: KeyState, // LMB

pub fn Init(alloc: Allocator, backend: GUBackend, base_layout: ?GULayout) GU {
    return GU{
        .allocator = alloc,
        .label_arena = .init(alloc),
        .backend = backend,
        .fonts = .empty,
        .textures = .empty,
        .element_tree = .empty,
        .element_stack = .empty,
        .element_line_stack = .empty,
        .clip_stack = .empty,
        .buttons = .init(alloc),
        .button_delete_queue = .empty,
        .btn_mode_stack = .empty,
        .btn_style_arena = .empty,
        .btn_style_stack_padding_ver = .empty,
        .btn_style_stack_padding_hor = .empty,
        .btn_style_stack_corner_rad = .empty,
        .btn_style_stack_corner_shape = .empty,
        .btn_style_stack_color_idle = .empty,
        .btn_style_stack_color_hover = .empty,
        .btn_style_stack_color_down = .empty,
        .btn_style_stack_changed = false,
        .render_commands = .empty,
        .render_commands_rect = .empty,
        .render_commands_text = .empty,
        .render_commands_clip = .empty,
        .base_layout = base_layout orelse .default,
        .mouse_pt = .{ .x = -1, .y = -1 },
        .element_queue_line_break = false,
        .element_sibling = null,
        .mouse_left = .default,
    };
}

pub fn Deinit(self: *GU) void {
    self.label_arena.deinit();
    self.btn_mode_stack.deinit(self.allocator);
    self.btn_style_arena.deinit(self.allocator);
    self.btn_style_stack_padding_ver.deinit(self.allocator);
    self.btn_style_stack_padding_hor.deinit(self.allocator);
    self.btn_style_stack_corner_rad.deinit(self.allocator);
    self.btn_style_stack_corner_shape.deinit(self.allocator);
    self.btn_style_stack_color_idle.deinit(self.allocator);
    self.btn_style_stack_color_hover.deinit(self.allocator);
    self.btn_style_stack_color_down.deinit(self.allocator);
    self.render_commands.deinit(self.allocator);
    self.render_commands_rect.deinit(self.allocator);
    self.render_commands_text.deinit(self.allocator);
    self.render_commands_clip.deinit(self.allocator);
    self.clip_stack.deinit(self.allocator);
    self.element_line_stack.deinit(self.allocator);
    self.element_stack.deinit(self.allocator);
    self.element_tree.deinit(self.allocator);
    self.textures.deinit(self.allocator);
    self.fonts.deinit(self.allocator);
}

//------------------------------------------------------------------------------
// RESOURCES

// TODO: impl handle-based system
pub fn AddFont(self: *GU, font: GUFontAtlas) !usize {
    try self.fonts.append(self.allocator, font);
    return self.fonts.items.len - 1;
}

// TODO: impl handle-based system
pub fn AddTexture(self: *GU, texture: GUTextureAtlas) !usize {
    try self.textures.append(self.allocator, texture);
    return self.textures.items.len - 1;
}

//------------------------------------------------------------------------------
// FRAME

pub fn BeginFrame(self: *GU) !void {
    assert(self.element_stack.items.len == 0);
    assert(self.element_line_stack.items.len == 0);
    assert(self.btn_mode_stack.items.len == 0);

    const surface_size = self.backend.GetSurfaceDimensions();

    _ = self.label_arena.reset(.retain_capacity);
    self.ResetButtonStyle();
    self.render_commands.clearRetainingCapacity();
    self.render_commands_rect.clearRetainingCapacity();
    self.render_commands_text.clearRetainingCapacity();
    self.render_commands_clip.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    self.element_line_stack.append(self.allocator, zeroInit(GULineData, .{ .line = 1 })) catch unreachable;
    if (!self.DoElement(&self.base_layout)) unreachable;
    const element = self.GetElement();
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    element.area.w = surface_size.x;
    element.area.h = surface_size.y;
}

// TODO: initial element sizing as an explicit pass separate from the initial
// element tree generation?
pub fn EndFrame(self: *GU) void {
    self.EndElement(); // close base layout container
    _ = self.element_line_stack.pop();

    self.backend.BeginRendering();

    self.DoElementLineBreakParsing();
    self.DoElementPositioning();
    self.DoButtonPostProcessing();
    self.DoElementEmitDrawCommands();
    //self.DoElementDebugLog();

    for (self.render_commands.items) |cmd| {
        switch (cmd.kind) {
            .rect => self.backend.DrawRect(&self.render_commands_rect.items[cmd.handle]),
            .text => self.backend.DrawString(&self.render_commands_text.items[cmd.handle]),
            .clip => self.backend.SetClip(&self.render_commands_clip.items[cmd.handle]),
        }
    }

    self.backend.EndRendering();
}

//------------------------------------------------------------------------------
// LAYOUT PASSES

// FIXME: cleanup/streamline, maybe split into multiple passes if that makes sense
// TODO: rename to DoElementResizeAndParseLineBreaks ??
// TODO: update for text wrapping; will need to assert no padding/gaps, and remove
// .Fixed assertion for labels in EndElement
/// inserts line break markers where needed, and updates parent dimensions in
/// case of line breaks occurring
fn DoElementLineBreakParsing(self: *GU) void {
    assert(self.element_line_stack.items.len == 0);
    defer assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(GULineData, .{ .line = 1 });
    var ld: *GULineData = &ld_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        const p: ?*Element = if (e.parent) |pa_i| &self.element_tree.items[pa_i] else null;

        if (it_data.relation == .Child) {
            stack.appendAssumeCapacity(zeroInit(GULineData, .{
                .parent_padding = p.?.layout.padding,
                .parent_gaps = p.?.layout.gaps,
            })); // capacity set during initial tree gen
            ld = &stack.items[stack.items.len - 1];
        }

        if (it_data.relation == .Parent) {
            if (!e.layout.mode_w.IsPreComputable())
                e.area.w = @max(ld.max_w, ld.current_w + ld.AxisSpacing(.Main, ld.current_items));
            if (!e.layout.mode_h.IsPreComputable())
                e.area.h = ld.current_h + ld.current_y + ld.AxisSpacing(.Cross, ld.line);

            _ = self.element_line_stack.pop();
            ld = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &ld_base;
        }

        if (it_data.relation != .Parent) {
            if (e.layout.mode_w == .Stretch)
                e.area.w = @max(p.?.area.w + e.area.w - ld.AxisSpacing(.Main, p.?.layout.widths.?.len), 0);
            if (e.layout.mode_h == .Stretch)
                e.area.h = @max(p.?.area.h + e.area.h - ld.AxisSpacing(.Cross, p.?.layout.heights.?.len), 0);
        }

        if (p != null and
            p.?.layout.auto_line_break and
            p.?.layout.widths == null and
            p.?.layout.mode_w.IsPreComputable() and
            ld.current_w + ld.parent_gaps.x + e.area.w > p.?.area.w - ld.parent_padding.x * 2)
            e.features.bLineBreak = true;

        if (it_data.relation == .Child or e.features.bLineBreak) {
            ld.max_w = @max(ld.max_w, ld.current_w + ld.AxisSpacing(.Main, ld.current_items));
            ld.line += 1;
            ld.current_y += ld.current_h;
            ld.current_w = 0;
            ld.current_h = 0;
            ld.current_items = 0;
        }

        ld.current_items += 1;
        ld.current_w += e.area.w;
        ld.current_h = @max(ld.current_h, e.area.h);
    }
}

fn DoElementPositioning(self: *GU) void {
    assert(self.element_line_stack.items.len == 0);
    defer assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(GULineData, .{});
    var ld: *GULineData = &ld_base;
    var p: ?*Element = null;

    var it = ElementIterator.Init(self.element_tree.items);
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
            stack.appendAssumeCapacity(zeroInit(GULineData, .{})); // capacity set during initial tree gen
            ld = &stack.items[stack.items.len - 1];
            e.area.x = p.?.area.x + p.?.layout.padding.x;
            e.area.y = p.?.area.y + p.?.layout.padding.y;
            ld.current_y = e.area.y;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        const gaps = if (p != null) p.?.layout.gaps else Vec2.zero;

        if (e.features.bLineBreak) {
            const pos = if (p != null) p.?.area.toPos() else Vec2.zero;
            const padding = if (p != null) p.?.layout.padding else Vec2.zero;
            e.area.x = pos.x + padding.x;
            e.area.y = ld.current_y + ld.current_h + gaps.y;
            ld.current_y = e.area.y;
            ld.current_h = e.area.h;
        } else {
            const area = if (e.sibling_prev) |s| self.element_tree.items[s].area else Rect.zero;
            e.area.x = area.x + area.w + gaps.x;
            e.area.y = ld.current_y;
            ld.current_h = @max(ld.current_h, e.area.h);
        }
    }
}

fn DoElementEmitDrawCommands(self: *GU) void {
    assert(self.element_stack.items.len == 0);
    assert(self.clip_stack.items.len == 0);
    defer assert(self.element_stack.items.len == 0);
    defer assert(self.clip_stack.items.len == 0);

    const stack = &self.clip_stack;
    const sd = self.backend.GetSurfaceDimensions();
    const c_base = Rect{ .x = 0, .y = 0, .w = sd.x, .h = sd.y };
    var next_clip = self.render_commands_clip.items.len;
    self.render_commands.append(self.allocator, .init(.clip, next_clip)) catch |err|
        std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
    self.render_commands_clip.append(self.allocator, .{ .area = c_base }) catch |err|
        std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
    var c: *const Rect = &c_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (!e.area.IsCollidingRect(c)) continue;

        if (it_data.relation == .Parent) {
            _ = stack.pop();
            c = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &c_base;
            next_clip = self.render_commands_clip.items.len;
            self.render_commands.append(self.allocator, .init(.clip, next_clip)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            self.render_commands_clip.append(self.allocator, .{ .area = c.* }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            continue;
        }

        defer if (it_data.relation != .Parent and e.first_child != null) {
            stack.append(self.allocator, e.area.GetIntersection(c)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Clip Stack ({s})", .{@errorName(err)});
            c = &stack.items[stack.items.len - 1];

            next_clip = self.render_commands_clip.items.len;
            self.render_commands.append(self.allocator, .init(.clip, next_clip)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            self.render_commands_clip.append(self.allocator, .{ .area = c.* }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
        };

        // is it actually drawable?
        if (Color.fromInt(e.layout.color).a == 0) continue;
        if (!e.area.AreaIsNonZero()) continue;

        if (e.features.bShowRect) {
            var cmd: RCRect = .init(e.area, e.layout.corner, e.layout.color);

            if (e.features.bShowTexture) cmd.texture = &self.textures.items[e.texture];

            const next_rect = self.render_commands_rect.items.len;
            self.render_commands.append(self.allocator, .init(.rect, next_rect)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            self.render_commands_rect.append(self.allocator, cmd) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
        }

        if (e.features.bShowLabel and e.label_str.len > 0) {
            // FIXME: need a way to ensure that the text gets drawn after (i.e.
            //  on top), because they will both be emitted at the same time
            //  and the renderer may not respect the call order if batching;
            //  maybe add a "batch layer" value to draw cmd, and give labels
            //  a half-value extra so that they are intereted as upper layer.
            const cmd: RCText = .{
                .pos = e.area.toPos(),
                .font = &self.fonts.items[e.label_font],
                .color = e.layout.color,
                .str = e.label_str,
            };

            const next_text = self.render_commands_text.items.len;
            self.render_commands.append(self.allocator, .init(.text, next_text)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            self.render_commands_text.append(self.allocator, cmd) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
        }
    }
}

fn DoElementDebugLog(self: *GU) void {
    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        std.log.debug(
            "it-element: ({*})  {t: <12}{d}x{d}",
            .{ e, it_data.relation, e.area.w, e.area.h },
        );
    }
}

fn DoButtonPostProcessing(self: *GU) void {
    assert(self.button_delete_queue.items.len == 0);

    var it = self.buttons.iterator();
    while (it.next()) |btn_info| {
        const btn = btn_info.value_ptr;

        btn.Update(
            &self.mouse_pt,
            self.mouse_left.just_down,
            self.mouse_left.just_up,
        );

        if (btn.element == maxInt(usize)) {
            self.button_delete_queue.append(self.allocator, btn_info.key_ptr.*) catch |err|
                std.debug.panic("DoButtonPostProcessing ({s})", .{@errorName(err)});
            continue;
        }
        btn.area = self.element_tree.items[btn.element].area;
        btn.element = maxInt(usize);
    }

    while (self.button_delete_queue.pop()) |item|
        _ = self.buttons.remove(item);
}

//------------------------------------------------------------------------------
// LAYOUT

/// returns whether creating a new container was successful. guarantees the element
/// tree will be in a valid state (i.e. the same as before calling, on failure).
pub fn DoElement(self: *GU, layout: ?*const GULayout) bool {
    if (layout) |lo| {
        if (lo.widths) |w| assert(w.len > 0);
        if (lo.heights) |h| assert(h.len > 0);
    }

    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const element_i = self.element_tree.items.len; // next index will equal len

    const ld: *GULineData = &self.element_line_stack.items[self.element_line_stack.items.len - 1];

    self.element_tree.append(self.allocator, e: {
        var e: Element = .empty;
        e.layout = if (layout) |lo| lo.* else .default;
        e.id = element_i;
        e.parent = parent_i;
        e.sibling_prev = self.element_sibling;
        e.features.bShowRect = e.layout.color & 0xFF > 0; // FIXME: hacky
        break :e e;
    }) catch return false;

    self.element_stack.append(self.allocator, element_i) catch {
        _ = self.element_tree.pop();
        return false;
    };

    const parent: ?*Element = if (parent_i) |i| &self.element_tree.items[i] else null;
    const element: *Element = &self.element_tree.items[element_i];

    if (self.element_queue_line_break or
        (parent != null and parent.?.layout.widths != null and
            ld.current_items == parent.?.layout.widths.?.len))
    {
        self.element_queue_line_break = false;
        ld.line += 1;
        ld.current_items = 0;
        element.features.bLineBreak = true;
    }
    ld.current_items += 1;

    if (parent) |pa| {
        if (pa.first_child == null) pa.first_child = element_i;
        if (pa.layout.widths) |widths| {
            element.area.w = widths[(ld.current_items - 1) % widths.len];
            element.layout.mode_w = GUDimensionMode.ParseAuto(element.area.w);
        }
        if (pa.layout.heights) |heights| {
            element.area.h = heights[(ld.line - 1) % heights.len];
            element.layout.mode_h = GUDimensionMode.ParseAuto(element.area.h);
        }
        pa.children += 1; // FIXME: now redundant with line break parsing implemented?
    }

    if (self.element_sibling) |sibling| {
        self.element_tree.items[sibling].sibling_next = element_i;
        self.element_sibling = null;
    }

    self.element_line_stack.append(self.allocator, zeroInit(GULineData, .{ .line = 1 })) catch |err|
        std.debug.panic("DoElement: ({s})", .{@errorName(err)});
    return true;
}

/// Finalize the current element. Element validation happens at this point, so
/// any references to the element (e.g. from `GetElement`) must not be used
/// after this is called.
pub fn EndElement(self: *GU) void {
    _ = self.element_line_stack.pop();
    const element_i = self.element_stack.pop().?;
    const element: *Element = &self.element_tree.items[element_i];
    const parent: ?*Element = if (element.parent) |p| &self.element_tree.items[p] else null;
    self.element_sibling = element_i;
    self.element_queue_line_break = false; // cleanup unused line break

    if (element.layout.mode_w == .Stretch) {
        assert(parent != null);
        assert(parent.?.layout.widths != null);
        assert(parent.?.layout.mode_w.IsPreComputable());
        assert(element.area.w < 0);
    }
    if (element.layout.mode_h == .Stretch) {
        assert(parent != null);
        assert(parent.?.layout.heights != null);
        assert(parent.?.layout.mode_h.IsPreComputable());
        assert(element.area.h < 0);
    }

    // Button
    if (element.features.bClickable) {
        // button state setup
        const btn: *const Button = btn: {
            const btn_key = self.GetElementKey(element);
            const btn_info = self.buttons.getOrPut(btn_key) catch break :btn &.empty;

            // TODO: button mode should come from push stack (currently defaults .Press)
            const btn = btn_info.value_ptr;
            if (!btn_info.found_existing) btn.* = .empty;
            btn.element = element.id;
            btn.mode = self.btn_mode_stack.getLastOrNull() orelse ButtonMode.default;
            break :btn btn;
        };

        // visual updating
        const btn_style = &self.btn_style_arena.items[self.GetButtonStyle()];
        element.layout.color = switch (btn.state) {
            .Idle => if (element.features.bClickDepressed) btn_style.ColorDown else btn_style.ColorIdle,
            .Hover => if (element.features.bClickDepressed) btn_style.ColorIdle else btn_style.ColorHover,
            .Down => btn_style.ColorDown,
        };
        element.layout.padding = .{ .x = btn_style.PaddingHor, .y = btn_style.PaddingVer };
        element.layout.corner = .{ .radius = btn_style.CornerRad, .style = btn_style.CornerShape };
    }

    // Texture: behaviour of sizing the element with relation to the texture (e.g.
    // "draw image = match texture size with fixed sizing") is left to the widget impl
    if (element.features.bShowTexture) {
        assert(element.features.bShowRect == true);
        assert(element.texture != maxInt(usize)); // TODO: proper/safe "null texture" value
    }

    // Text
    //  - if the user wants text with a background then they are forced to wrap
    //    the text in an element, as this usage naturally covers normal aesthetic
    //    background needs without us needing to add complexity to the backend passes
    //  - 0-len string is allowed in order to accommodate dynamic text, but the
    //    rest is asserted regardless under the assumption that it is
    //  - behaviour of sizing the element with relation to string size is left
    //    to the widget impl
    if (element.features.bShowLabel) {
        assert(element.features.bShowRect == false);
        assert(element.label_font != maxInt(usize)); // TODO: proper/safe "null font" value
        //assert(element.label_str.len > 0);
    }
}

/// returns pointer to current element. pointer is only guaranteed to be valid
/// until the next call to DoElement
pub inline fn GetElement(self: *GU) *Element {
    const i = self.element_stack.getLast();
    return &self.element_tree.items[i];
}

// TODO: don't take element directly?
// TODO: more robust hashing strategy that doesn't cause hover state to break on
//  buttons that change where the button is in the element tree (e.g. by inserting
//  or removing an element above the button)
pub fn GetElementKey(self: *GU, element: *const Element) []const u8 {
    return std.fmt.allocPrint(self.allocator, "{X:0>16}{s}", .{ element.id, element.name }) catch &.{};
}

// TODO: don't take element directly?
pub fn GetElementClicked(self: *GU, element: *const Element) bool {
    const btn_key = self.GetElementKey(element);
    const btn: Button = self.buttons.get(btn_key) orelse .empty;
    return btn.activated;
}

pub fn SetElementColor(self: *GU, color: u32) void {
    const element = self.GetElement();
    element.layout.color = color;
}

pub fn SetElementPadding(self: *GU, padding: Vec2) void {
    const element = self.GetElement();
    element.layout.padding = padding;
}

pub fn SetElementGaps(self: *GU, gaps: Vec2) void {
    const element = self.GetElement();
    element.layout.gaps = gaps;
}

pub fn SetElementSize(self: *GU, w: f32, h: f32) void {
    const element = self.GetElement();
    element.area.w = w;
    element.area.h = h;
}

//------------------------------------------------------------------------------
// STACKS

// FIXME: (button styles) the actual indexing of the arena could behave like a
//  stack, thereby avoiding unnecessary pushing of redundant styles, no?

/// returns `btn_style_arena` index for current button style configuration.
fn GetButtonStyle(self: *GU) usize {
    assert(self.btn_style_arena.items.len > 0);

    if (self.btn_style_stack_changed)
        self.GenerateButtonStyle();

    return self.btn_style_arena.items.len - 1;
}

fn GenerateButtonStyle(self: *GU) void {
    assert(self.btn_style_stack_changed == true);
    assert(self.btn_style_stack_padding_ver.items.len > 0);
    assert(self.btn_style_stack_padding_hor.items.len > 0);
    assert(self.btn_style_stack_corner_rad.items.len > 0);
    assert(self.btn_style_stack_corner_shape.items.len > 0);
    assert(self.btn_style_stack_color_idle.items.len > 0);
    assert(self.btn_style_stack_color_hover.items.len > 0);
    assert(self.btn_style_stack_color_down.items.len > 0);

    self.btn_style_stack_changed = false;
    self.btn_style_arena.append(self.allocator, ButtonStyle{
        .PaddingVer = self.btn_style_stack_padding_ver.getLast(),
        .PaddingHor = self.btn_style_stack_padding_hor.getLast(),
        .CornerRad = self.btn_style_stack_corner_rad.getLast(),
        .CornerShape = self.btn_style_stack_corner_shape.getLast(),
        .ColorIdle = self.btn_style_stack_color_idle.getLast(),
        .ColorHover = self.btn_style_stack_color_hover.getLast(),
        .ColorDown = self.btn_style_stack_color_down.getLast(),
    }) catch |e| std.log.err("(GenerateButtonStyle) ERROR: {t}", .{e});
}

fn ResetButtonStyle(self: *GU) void {
    self.btn_style_arena.clearRetainingCapacity();
    self.btn_style_stack_padding_ver.clearRetainingCapacity();
    self.btn_style_stack_padding_hor.clearRetainingCapacity();
    self.btn_style_stack_corner_rad.clearRetainingCapacity();
    self.btn_style_stack_corner_shape.clearRetainingCapacity();
    self.btn_style_stack_color_idle.clearRetainingCapacity();
    self.btn_style_stack_color_hover.clearRetainingCapacity();
    self.btn_style_stack_color_down.clearRetainingCapacity();
    self.InitButtonStyle();
}

fn InitButtonStyle(self: *GU) void {
    assert(self.btn_style_arena.items.len == 0);
    assert(self.btn_style_stack_padding_ver.items.len == 0);
    assert(self.btn_style_stack_padding_hor.items.len == 0);
    assert(self.btn_style_stack_corner_rad.items.len == 0);
    assert(self.btn_style_stack_corner_shape.items.len == 0);
    assert(self.btn_style_stack_color_idle.items.len == 0);
    assert(self.btn_style_stack_color_hover.items.len == 0);
    assert(self.btn_style_stack_color_down.items.len == 0);
    self.PushButtonStyle(.default);
    self.GenerateButtonStyle();
}

//------------------------------------------------------------------------------
// BUTTON MODE API

pub fn PushButtonMode(self: *GU, mode: ButtonMode) void {
    self.btn_mode_stack.append(self.allocator, mode) catch |e|
        std.log.err("(PushButtonMode) ERROR: {t}", .{e});
}

pub fn PopButtonMode(self: *GU) void {
    _ = self.btn_mode_stack.pop();
}

//------------------------------------------------------------------------------
// BUTTON STYLE API

pub fn PushButtonStyle(self: *GU, style: ButtonStyle) void {
    self.btn_style_stack_padding_ver.append(self.allocator, style.PaddingVer) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_padding_hor.append(self.allocator, style.PaddingHor) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_corner_rad.append(self.allocator, style.CornerRad) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_corner_shape.append(self.allocator, style.CornerShape) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_color_idle.append(self.allocator, style.ColorIdle) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_color_hover.append(self.allocator, style.ColorHover) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_color_down.append(self.allocator, style.ColorDown) catch |e|
        std.log.err("(PushButtonStyle) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonPadding(self: *GU, vertical: f32, horizontal: f32) void {
    self.btn_style_stack_padding_ver.append(self.allocator, vertical) catch |e|
        std.log.err("(PushButtonPadding) ERROR: {t}", .{e});
    self.btn_style_stack_padding_hor.append(self.allocator, horizontal) catch |e|
        std.log.err("(PushButtonPadding) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonCorner(self: *GU, radius: f32, style: CornerShape) void {
    self.btn_style_stack_corner_rad.append(self.allocator, radius) catch |e|
        std.log.err("(PushButtonCorner) ERROR: {t}", .{e});
    self.btn_style_stack_corner_shape.append(self.allocator, style) catch |e|
        std.log.err("(PushButtonCorner) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonColor(self: *GU, idle: u32, hover: u32, down: u32) void {
    self.btn_style_stack_color_idle.append(self.allocator, idle) catch |e|
        std.log.err("(PushButtonColor) ERROR: {t}", .{e});
    self.btn_style_stack_color_hover.append(self.allocator, hover) catch |e|
        std.log.err("(PushButtonColor) ERROR: {t}", .{e});
    self.btn_style_stack_color_down.append(self.allocator, down) catch |e|
        std.log.err("(PushButtonColor) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonPaddingVertical(self: *GU, value: f32) void {
    self.btn_style_stack_padding_ver.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonPaddingVertical) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonPaddingHorizontal(self: *GU, value: f32) void {
    self.btn_style_stack_padding_hor.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonPaddingHorizontal) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonCornerRadius(self: *GU, value: f32) void {
    self.btn_style_stack_corner_rad.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonCornerRadius) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonCornerShape(self: *GU, value: CornerShape) void {
    self.btn_style_stack_corner_shape.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonCornerShape) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonColorIdle(self: *GU, value: u32) void {
    self.btn_style_stack_color_idle.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonColorIdle) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonColorHover(self: *GU, value: u32) void {
    self.btn_style_stack_color_hover.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonColorHover) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PushButtonColorDown(self: *GU, value: u32) void {
    self.btn_style_stack_color_down.append(self.allocator, value) catch |e|
        std.log.err("(PushButtonColorDown) ERROR: {t}", .{e});
    self.btn_style_stack_changed = true;
}

pub fn PopButtonStyle(self: *GU) void {
    _ = self.btn_style_stack_padding_ver.pop();
    _ = self.btn_style_stack_padding_hor.pop();
    _ = self.btn_style_stack_corner_rad.pop();
    _ = self.btn_style_stack_corner_shape.pop();
    _ = self.btn_style_stack_color_idle.pop();
    _ = self.btn_style_stack_color_hover.pop();
    _ = self.btn_style_stack_color_down.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonPadding(self: *GU) void {
    _ = self.btn_style_stack_padding_ver.pop();
    _ = self.btn_style_stack_padding_hor.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonCorner(self: *GU) void {
    _ = self.btn_style_stack_corner_rad.pop();
    _ = self.btn_style_stack_corner_shape.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonColor(self: *GU) void {
    _ = self.btn_style_stack_color_idle.pop();
    _ = self.btn_style_stack_color_hover.pop();
    _ = self.btn_style_stack_color_down.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonPaddingVertical(self: *GU) void {
    _ = self.btn_style_stack_padding_ver.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonPaddingHorizontal(self: *GU) void {
    _ = self.btn_style_stack_padding_hor.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonCornerRadius(self: *GU) void {
    _ = self.btn_style_stack_corner_rad.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonCornerShape(self: *GU) void {
    _ = self.btn_style_stack_corner_shape.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonColorIdle(self: *GU) void {
    _ = self.btn_style_stack_color_idle.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonColorHover(self: *GU) void {
    _ = self.btn_style_stack_color_hover.pop();
    self.btn_style_stack_changed = true;
}

pub fn PopButtonColorDown(self: *GU) void {
    _ = self.btn_style_stack_color_down.pop();
    self.btn_style_stack_changed = true;
}

//------------------------------------------------------------------------------
// WIDGETS

// TODO: stretch-like rect dimensions
pub fn DoRect(self: *GU, size: Vec2, color: u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowRect = true;
    element.area.w = size.x;
    element.area.h = size.y;
    element.layout.color = color;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
}

pub fn DoImage(self: *GU, texture: TextureHandle, color: ?u32, scale: f32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowTexture = true;
    element.features.bShowRect = true;
    element.texture = texture;
    element.layout.color = color orelse 0xFFFFFFFF;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    const texture_size = &self.textures.items[element.texture].Size();
    element.area.w = scale * texture_size.x;
    element.area.h = scale * texture_size.y;
}

// TODO: add formatting, like standard string formatting functions
pub fn DoLabel(self: *GU, font: ?FontHandle, color: ?u32, comptime fmt: []const u8, args: anytype) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    const str = std.fmt.allocPrint(self.label_arena.allocator(), fmt, args) catch |err|
        std.debug.panic("DoLabel failed to allocate string: ({s})", .{@errorName(err)});
    element.features.bShowLabel = true;
    element.label_font = font orelse 0;
    element.label_str = str;
    element.layout.color = color orelse 0xFFFFFFFF;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    const label_size = &self.fonts.items[element.label_font].StringSize(element.label_str);
    element.area.w = label_size.x;
    element.area.h = label_size.y;
}

// FIXME: remove font as input, use font stack
// NOTE: id hash uses input fmt, not resolved formatted string
/// returns whether button was 'activated' (pressed)
pub fn DoButton(self: *GU, font: ?FontHandle, comptime fmt: []const u8, args: anytype) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bClickable = true;
    element.features.bShowRect = true;
    element.name = fmt;

    self.DoLabel(font, null, fmt, args);

    return self.GetElementClicked(element);
}

// FIXME: remove font as input, use font stack
// NOTE: id hash uses input fmt, not resolved formatted string
/// same general behaviour as DoButton, but updates an 'active' bool for you.
/// if button is culled (due to not rendering, clip culling, etc.), the external
/// bool will NOT be toggled
/// returns whether button was 'activated' (pressed and subsequently toggled)
pub fn DoToggleButton(self: *GU, active: *bool, font: ?FontHandle, comptime fmt: []const u8, args: anytype) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bClickable = true;
    element.features.bShowRect = true;
    element.name = fmt;

    const activated = self.GetElementClicked(element);
    if (active.*) element.features.bClickDepressed = true;
    if (activated) active.* = !active.*;

    self.DoLabel(font, null, fmt, args);

    return activated;
}

pub fn DoLineBreak(self: *GU) void {
    self.element_queue_line_break = true;
}
