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

// TODO: ?? add CanDrawString to check against supported character range in font impl
pub const Backend = struct {
    ptr: *anyopaque,
    fnSurfaceSize: *const fn (*anyopaque) Vec2,
    fnCustomCommandEmit: *const fn (*anyopaque, *const RCCustom) void,
    fnRectDraw: *const fn (*anyopaque, *const RCRect) void,
    fnStringDraw: *const fn (*anyopaque, *const RCText) void,
    fnStringSize: *const fn (*anyopaque, font: FontHandle, []const u8) Vec2,
    fnTextureSize: *const fn (*anyopaque, font: TextureHandle) Vec2,
    fnClipSet: *const fn (*anyopaque, *const RCClip) void,
    fnRenderBegin: *const fn (*anyopaque) void,
    fnRenderEnd: *const fn (*anyopaque) void,

    pub fn SurfaceSize(self: *Backend) Vec2 {
        return self.fnSurfaceSize(self.ptr);
    }

    pub fn CustomCommandEmit(self: *Backend, cmd: *const RCCustom) void {
        self.fnCustomCommandEmit(self.ptr, cmd);
    }

    // TODO: impl texture tile drawing, see RenderCommand->Rect
    pub fn RectDraw(self: *Backend, cmd: *const RCRect) void {
        self.fnRectDraw(self.ptr, cmd);
    }

    pub fn StringDraw(self: *Backend, cmd: *const RCText) void {
        self.fnStringDraw(self.ptr, cmd);
    }

    pub fn StringSize(self: *Backend, font: FontHandle, str: []const u8) Vec2 {
        return self.fnStringSize(self.ptr, font, str);
    }

    pub fn TextureSize(self: *Backend, texture: TextureHandle) Vec2 {
        return self.fnTextureSize(self.ptr, texture);
    }

    pub fn ClipSet(self: *Backend, cmd: *const RCClip) void {
        self.fnClipSet(self.ptr, cmd);
    }

    /// called as a way to signal to the backend that we are about to render a
    /// frame, and give it a 'hook' to do any related setup (store clip state, etc.)
    pub fn RenderBegin(self: *Backend) void {
        self.fnRenderBegin(self.ptr);
    }

    /// a 'hook' for the backend to cleanup after we're done with a frame
    pub fn RenderEnd(self: *Backend) void {
        self.fnRenderEnd(self.ptr);
    }
};

//------------------------------------------------------------------------------

// FIXME: don't really like having the field types separated, but afaik needed to
// pass their types to function params (see Backend); investigate to confirm
// that it's actually not possible/practical to reference the field type directly
// WARN: also, not sure it's necessarily a good idea to obfuscate the field members
// when calling the Backend functions; however, it makes for cleaner fn defs
// and theoretically cuts down on stack thrashing (to compare/confirm), need to
// make a final call on which way to do it
pub const RenderCommand = struct {
    kind: Kind,
    handle: usize, // TODO: actual handle impl

    pub const Kind = enum {
        custom,
        rect,
        text,
        clip,

        pub fn toPayloadT(k: Kind) type {
            return switch (k) {
                .custom => RCCustom,
                .text => RCText,
                .rect => RCRect,
                .clip => RCClip,
            };
        }
    };

    pub fn init(kind: Kind, handle: usize) RenderCommand {
        return .{ .handle = handle, .kind = kind };
    }
};

// TODO: user-defined resource handle types
pub const FontHandle = usize;
pub const TextureHandle = usize;
pub const CustomActionHandle = usize;

// TODO: ?? add field for data ptr/handle? with only action id, the implementation
//  will need to register separate actions for equivalent behaviours operating
//  on different data. not the end of the world, but..
// NOTE: should mirror RCRect, minus texture-related fields. the idea is that
//  the custom command will use the rect info as context so that it knows the
//  region in which to enact the action, and if it ends up drawing to it directly,
//  the drawing essentially replaces what would be the body of an RCRect call.
pub const RCCustom = struct {
    action: CustomActionHandle, // implementation-defined action id
    rect: Rect,
    corner_radius: f32,
    corner_shape: CornerShape,
    color: u32,
};

pub const RCRect = struct {
    rect: Rect,
    corner_radius: f32,
    corner_shape: CornerShape,
    color: u32,
    texture: TextureHandle,
    tile: ?u32, // for texture atlases
};

pub const RCText = struct {
    str: []const u8,
    font: FontHandle,
    pos: Vec2,
    color: u32,
};

pub const RCClip = struct {
    area: Rect,
};

//------------------------------------------------------------------------------

// TODO: rename to something more appropriate?
/// inter-frame button state tracking, associated with element via hashtable
pub const Button = struct {
    mode: ButtonMode,
    state: ButtonState,
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
                    //std.log.debug("button activated! (press)", .{});
                    self.activated = true;
                    return;
                }
            }

            if (self.state == .Down and btn_just_up) {
                self.state = .Hover;
                if (self.mode == .Release) {
                    //std.log.debug("button activated! (release)", .{});
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
};

pub const KeyState = struct {
    down: bool,
    just_up: bool,
    just_down: bool,
    accumulator_down: bool,
    accumulator_changes: u32,

    pub const start: KeyState = .{
        .down = false,
        .just_up = false,
        .just_down = false,
        .accumulator_down = false,
        .accumulator_changes = 0,
    };

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

pub const Element = struct {
    id: usize,
    parent: ?usize,
    children: usize,
    first_child: ?usize,
    sibling_next: ?usize,
    sibling_prev: ?usize,

    features: ElementFeatures,
    layout: Layout,
    area: Rect,
    clip: Rect, // the clipping region this element applies to its children
    gap: Vec2, // calculated space between this element and the previous sibling (x) and line (y)
    fill: Vec2, // FIXME: unused; how big the element is for layout calculations
    texture: TextureHandle,
    name: []const u8, // primary key used for hashing element for cross-frame identification
    data: usize, // secondary key used in the absence of `name`, typically a unique pointer
    label_str: []const u8,
    label_font: FontHandle,
    custom_action: CustomActionHandle, // impl-defined action associated with custom command

    const empty: Element = .{
        .layout = .blank,
        .area = .zero,
        .clip = .zero,
        .fill = .zero,
        .gap = .zero,
        .id = 0,
        .parent = null,
        .children = 0,
        .first_child = null,
        .sibling_next = null,
        .sibling_prev = null,
        .features = .none,
        .texture = 0,
        .name = &.{},
        .label_str = &.{},
        .label_font = 0,
        .data = 0,
        .custom_action = maxInt(usize),
    };

    inline fn HashKey(element: *const Element) []const u8 {
        if (element.name.len > 0) return element.name;

        assert(element.data != 0);
        return std.mem.asBytes(&element.data);
    }
};

// TODO: ?? rename bShowRect -> bShowBody or bShowBackground
// TODO: body shadow
// TODO: body outline
// TODO: body absolute positioning (like CSS)
// TODO: body relative positioning (like CSS)
// TODO: body contents scrollable, on X and Y individually
// TODO: texture tiling
// TODO: texture scaling
// TODO: texture stretch to rect size
// TODO: texture treated as 9grid
// TODO: text shadow
// TODO: text outline
// TODO: clickable element is draggable, on X and Y individually (require abs/rel pos)
// TODO: enable clipping (i.e. "allow/disallow visual overflow")
pub const ElementFeatures = packed struct(u32) {
    // Visual functionality
    bShowRect: bool, // render the body of the element
    bShowTexture: bool, // use a texture on the element body
    bShowLabel: bool,

    // Layout functionality
    bLineBreak: bool,
    /// space children based on active font instead of gaps setting
    bTextSpacing: bool,
    /// set prev gap-x to 0
    bConsumeGapX: bool,
    /// set prev gap-y to 0 if current line only contains elements with this flag
    bConsumeGapY: bool, // FIXME: impl
    /// set next gap-x to 0
    bConsumeNextGapX: bool,
    /// set next gap-y to 0 if current line only contains elements with this flag
    bConsumeNextGapY: bool, // FIXME: impl
    /// if element would trigger a line break, collapse and make next element break instead
    bOverflowCollapseX: bool,

    // Button functionality
    bClickable: bool,
    bClickDown: bool, // FIXME: does nothing
    bClickHover: bool, // FIXME: does nothing
    /// button visually "idles" in down-state
    bClickDepressed: bool,
    /// button visually looks like a regular element (does not apply button styling)
    bClickNoStyle: bool,

    // Misc. functionality
    bCustomCommand: bool,

    _: u16,

    const none: ElementFeatures = @bitCast(@as(u32, 0));
    const all: ElementFeatures = @bitCast(maxInt(u32));
};

// TODO: specify traversal order during Init, as a convenience so that user doesn't
// have to manually skip items when it's order-based
/// depth-first walk of element tree with pre- and post-order traversal; elements
/// with children are touched both on the way down and up, i.e. once before then
/// again after any children are walked
pub const ElementIterator = struct {
    source: []Element,
    this: ?usize,
    prev: ?usize,

    pub const ElementRelation = enum { Root, Child, Sibling, Parent };

    pub const ElementIt = struct {
        element: *Element,
        relation: ElementRelation,
    };

    pub fn Init(source: []Element) ElementIterator {
        return ElementIterator{
            .source = source,
            .this = null,
            .prev = null,
        };
    }

    pub fn Next(self: *ElementIterator) ?ElementIt {
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

pub const Layout = struct {
    mode_w: DimensionMode, // derived from parent 'widths' field if .Auto
    mode_h: DimensionMode, // derived from parent 'heights' field if .Auto
    color: u32,
    corner_radius: f32,
    corner_shape: CornerShape,
    widths: []const f32,
    heights: []const f32,
    padding: Vec2,
    gaps: Vec2,
    auto_line_break: bool,
    //scroll: ?

    const blank = zeroInit(Layout, .{});
};

/// implementation-defined shape id
/// typical values:
/// 0 = None (Square)
/// 1 = Round (Circle)
pub const CornerShape = u8;

// FIXME: Auto and Fit are not actually referenced anywhere??? so basically it's
//  assumed an element is Auto(Fit) if a dimension is not Stretch or Fixed, without
//  actually checking???
const DimensionMode = enum {
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
    fn ParseAuto(dimension: f32) DimensionMode {
        const sign = std.math.sign(dimension);
        if (sign == 1) return .Fixed;
        if (sign == 0) return .Fit;
        if (sign == -1) return .Stretch;
        unreachable;
    }

    /// Whether the dimension can be finalized before evaluating the size of any
    /// child elements.
    inline fn IsPreComputable(mode: DimensionMode) bool {
        return mode == .Fixed or mode == .Stretch;
    }
};

// TODO: reorganize? this is layouting pass stuff, not layout definition stuff
const LineData = struct {
    parent_padding: Vec2,
    parent_gaps: Vec2,
    line: u32,
    current_y: f32,
    current_h: f32,
    current_items: u32,
    current_w: f32,
    queue_line_break: bool,
    queue_consume_gap_x: bool,
    max_w: f32, // incl padding/gaps

    // TODO: impl axis def in Layout and derive
    pub inline fn AxisSpacing(self: *LineData, comptime axis: enum { Main, Cross }, items: usize) f32 {
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

//------------------------------------------------------------------------------

allocator: Allocator,

backend: Backend,

font_vstk: ValueStack(FontHandle),

element_tree: ArrayList(Element),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling
element_queue_line_break: bool,
element_line_stack: ArrayList(LineData),

clip_stack: ArrayList(Rect),
label_arena: ArenaAllocator,

base_layout: Layout,
base_button_style: ButtonStyle,
base_font: FontHandle,

buttons: StringHashMap(Button),
button_delete_queue: ArrayList([]const u8),
btn_mode_vstk: ValueStack(ButtonMode),

btn_style_arena: ArrayList(ButtonStyle), // arraylist for the typing/alignment, usage is like arena
btn_style_vstk_padding_ver: ValueStack(f32),
btn_style_vstk_padding_hor: ValueStack(f32),
btn_style_vstk_corner_rad: ValueStack(f32),
btn_style_vstk_corner_shape: ValueStack(CornerShape),
btn_style_vstk_color_idle: ValueStack(u32),
btn_style_vstk_color_hover: ValueStack(u32),
btn_style_vstk_color_down: ValueStack(u32),

render_commands: ArrayList(RenderCommand),
render_commands_cust: ArrayList(RCCustom),
render_commands_rect: ArrayList(RCRect),
render_commands_text: ArrayList(RCText),
render_commands_clip: ArrayList(RCClip),

mouse_pt: Vec2,
mouse_left: KeyState, // LMB

pub fn Init(
    alloc: Allocator,
    backend: Backend,
    base_layout: Layout,
    base_button_style: ButtonStyle,
    base_font: FontHandle,
) GU {
    return GU{
        .allocator = alloc,
        .label_arena = .init(alloc),
        .backend = backend,
        .element_tree = .empty,
        .element_stack = .empty,
        .element_line_stack = .empty,
        .clip_stack = .empty,
        .buttons = .init(alloc),
        .button_delete_queue = .empty,
        .btn_mode_vstk = .Init(alloc),
        .btn_style_arena = .empty,
        .btn_style_vstk_padding_ver = .Init(alloc),
        .btn_style_vstk_padding_hor = .Init(alloc),
        .btn_style_vstk_corner_rad = .Init(alloc),
        .btn_style_vstk_corner_shape = .Init(alloc),
        .btn_style_vstk_color_idle = .Init(alloc),
        .btn_style_vstk_color_hover = .Init(alloc),
        .btn_style_vstk_color_down = .Init(alloc),
        .font_vstk = .Init(alloc),
        .render_commands = .empty,
        .render_commands_cust = .empty,
        .render_commands_rect = .empty,
        .render_commands_text = .empty,
        .render_commands_clip = .empty,
        .base_layout = base_layout,
        .base_button_style = base_button_style,
        .base_font = base_font,
        .mouse_pt = .{ .x = -1, .y = -1 },
        .element_queue_line_break = false,
        .element_sibling = null,
        .mouse_left = .start,
    };
}

pub fn Deinit(self: *GU) void {
    self.label_arena.deinit();
    self.btn_mode_vstk.Deinit();
    self.btn_style_arena.deinit(self.allocator);
    self.btn_style_vstk_padding_ver.Deinit();
    self.btn_style_vstk_padding_hor.Deinit();
    self.btn_style_vstk_corner_rad.Deinit();
    self.btn_style_vstk_corner_shape.Deinit();
    self.btn_style_vstk_color_idle.Deinit();
    self.btn_style_vstk_color_hover.Deinit();
    self.btn_style_vstk_color_down.Deinit();
    self.render_commands.deinit(self.allocator);
    self.render_commands_cust.deinit(self.allocator);
    self.render_commands_rect.deinit(self.allocator);
    self.render_commands_text.deinit(self.allocator);
    self.render_commands_clip.deinit(self.allocator);
    self.clip_stack.deinit(self.allocator);
    self.element_line_stack.deinit(self.allocator);
    self.element_stack.deinit(self.allocator);
    self.element_tree.deinit(self.allocator);
    self.font_vstk.Deinit();
}

//------------------------------------------------------------------------------
// FRAME

pub fn BeginFrame(self: *GU) !void {
    assert(self.element_stack.items.len == 0);
    assert(self.element_line_stack.items.len == 0);
    assert(self.btn_mode_vstk.count == 0);
    assert(self.font_vstk.count == 0);

    const surface_size = self.backend.SurfaceSize();

    _ = self.label_arena.reset(.retain_capacity);
    self.btn_style_arena.clearRetainingCapacity();
    self.ButtonStyleStackStart();
    self.render_commands.clearRetainingCapacity();
    self.render_commands_cust.clearRetainingCapacity();
    self.render_commands_rect.clearRetainingCapacity();
    self.render_commands_text.clearRetainingCapacity();
    self.render_commands_clip.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    self.element_line_stack.append(self.allocator, zeroInit(LineData, .{ .line = 1 })) catch unreachable;
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
    self.ButtonStyleStackEnd();

    self.backend.RenderBegin();

    self.DoElementLineBreakParsing();
    self.DoElementPositioning();
    self.DoElementClipping();
    self.DoElementEmitRenderCommands();
    self.DoButtonPostProcessing();
    //self.DoElementDebugLog();

    for (self.render_commands.items) |cmd| {
        switch (cmd.kind) {
            .custom => self.backend.CustomCommandEmit(&self.render_commands_cust.items[cmd.handle]),
            .rect => self.backend.RectDraw(&self.render_commands_rect.items[cmd.handle]),
            .text => self.backend.StringDraw(&self.render_commands_text.items[cmd.handle]),
            .clip => self.backend.ClipSet(&self.render_commands_clip.items[cmd.handle]),
        }
    }

    self.backend.RenderEnd();
}

//------------------------------------------------------------------------------
// LAYOUT PASSES

// FIXME: cleanup/streamline, maybe split into multiple passes if that makes sense
// TODO: rename to DoElementResizeAndParseLineBreaks ??
/// inserts line break markers where needed, and updates parent dimensions in
/// case of line breaks occurring
fn DoElementLineBreakParsing(self: *GU) void {
    assert(self.element_line_stack.items.len == 0);
    defer assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(LineData, .{ .line = 1 });
    var ld: *LineData = &ld_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        const p: ?*Element = if (e.parent) |pa_i| &self.element_tree.items[pa_i] else null;
        const this_gap_y = ld.parent_gaps.y;
        var this_gap_x = ld.parent_gaps.x;
        if (e.features.bConsumeGapX or ld.queue_consume_gap_x) this_gap_x = 0;
        ld.queue_consume_gap_x = e.features.bConsumeNextGapX;

        // parent->child
        if (it_data.relation == .Child) {
            stack.appendAssumeCapacity(zeroInit(LineData, .{
                .parent_padding = p.?.layout.padding,
                .parent_gaps = p.?.layout.gaps,
            })); // capacity set during initial tree gen
            ld = &stack.items[stack.items.len - 1];
        }

        // child->parent
        if (it_data.relation == .Parent) {
            if (!e.layout.mode_w.IsPreComputable())
                e.area.w = @max(ld.max_w, ld.current_w + ld.AxisSpacing(.Main, ld.current_items));
            if (!e.layout.mode_h.IsPreComputable())
                e.area.h = ld.current_h + ld.current_y + ld.AxisSpacing(.Cross, ld.line);

            _ = self.element_line_stack.pop();
            ld = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &ld_base;
        }

        // root OR parent->child OR sibling->sibling
        if (it_data.relation != .Parent) {
            e.gap = .init(this_gap_x, this_gap_y);
            if (e.layout.mode_w == .Stretch)
                e.area.w = @max(p.?.area.w + e.area.w - ld.AxisSpacing(.Main, p.?.layout.widths.len), 0);
            if (e.layout.mode_h == .Stretch)
                e.area.h = @max(p.?.area.h + e.area.h - ld.AxisSpacing(.Cross, p.?.layout.heights.len), 0);
        }

        if (p != null and
            p.?.layout.auto_line_break and
            p.?.layout.widths.len == 0 and
            p.?.layout.mode_w.IsPreComputable() and
            ld.current_w + e.gap.x + e.area.w > p.?.area.w - ld.parent_padding.x * 2)
        {
            if (e.features.bOverflowCollapseX and !e.features.bLineBreak) {
                e.area.w = 0;
                e.area.h = 0;
                ld.queue_line_break = true;
                continue;
            }
            e.features.bLineBreak = true;
        }

        if (ld.queue_line_break) e.features.bLineBreak = true;
        ld.queue_line_break = false;

        if (it_data.relation == .Child or e.features.bLineBreak) {
            ld.max_w = @max(ld.max_w, ld.current_w + ld.AxisSpacing(.Main, ld.current_items));
            ld.line += 1;
            ld.current_y += ld.current_h;
            ld.current_w = e.area.w;
            ld.current_h = e.area.h;
            ld.current_items = 1;
            continue;
        }

        ld.current_items += 1;
        ld.current_w += e.area.w + e.gap.x;
        ld.current_h = @max(ld.current_h, e.area.h);
    }
}

// NOTE: simply assembles the final positions of everything; all the "calculated"
//  components that go into this should already be final before this runs.
fn DoElementPositioning(self: *GU) void {
    assert(self.element_line_stack.items.len == 0);
    defer assert(self.element_line_stack.items.len == 0);

    const stack = &self.element_line_stack;
    var ld_base = zeroInit(LineData, .{});
    var ld: *LineData = &ld_base;
    var p: ?*Element = null;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        // child->parent
        if (it_data.relation == .Parent) {
            _ = self.element_line_stack.pop();
            ld = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &ld_base;
            p = if (e.parent) |parent| &self.element_tree.items[parent] else null;
            continue;
        }

        // parent->child
        if (it_data.relation == .Child) {
            p = &self.element_tree.items[e.parent.?];
            stack.appendAssumeCapacity(zeroInit(LineData, .{})); // capacity set during initial tree gen
            ld = &stack.items[stack.items.len - 1];
            e.area.x = p.?.area.x + p.?.layout.padding.x;
            e.area.y = p.?.area.y + p.?.layout.padding.y;
            ld.current_y = e.area.y;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        if (e.features.bLineBreak) {
            const pos = if (p != null) p.?.area.toPos() else Vec2.zero;
            const padding = if (p != null) p.?.layout.padding else Vec2.zero;
            e.area.x = pos.x + padding.x;
            e.area.y = ld.current_y + ld.current_h + e.gap.y;
            ld.current_y = e.area.y;
            ld.current_h = e.area.h;
        } else {
            const area = if (e.sibling_prev) |s| self.element_tree.items[s].area else Rect.zero;
            e.area.x = area.x + area.w + e.gap.x;
            e.area.y = ld.current_y;
            ld.current_h = @max(ld.current_h, e.area.h);
        }
    }
}

fn DoElementClipping(self: *GU) void {
    assert(self.element_stack.items.len == 0);
    assert(self.clip_stack.items.len == 0);
    defer assert(self.element_stack.items.len == 0);
    defer assert(self.clip_stack.items.len == 0);

    const c_stack = &self.clip_stack;
    const sd = self.backend.SurfaceSize();
    const c_base = Rect{ .x = 0, .y = 0, .w = sd.x, .h = sd.y };
    var c = c_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (!e.area.IsCollidingRect(&c)) continue;

        // child->parent
        if (it_data.relation == .Parent) {
            _ = c_stack.pop();
            c = c_stack.getLastOrNull() orelse c_base;
            continue;
        }

        // apply regardless of whether current element is a parent, because it
        // affects things like mouse collision
        const next_clip = e.area.GetIntersection(&c);
        e.clip = next_clip;

        // unprocessed parent->child branch
        if (e.first_child != null) {
            c_stack.append(self.allocator, next_clip) catch |err|
                std.log.err("(DoElementClipping) ClipStack Append Error: {t}", .{err});
            c = c_stack.getLast();
        }
    }
}

fn EmitRenderCommand(
    self: *GU,
    comptime Kind: RenderCommand.Kind,
    payload: Kind.toPayloadT(),
) void {
    const cmdbuf = switch (Kind) {
        .custom => &self.render_commands_cust,
        .rect => &self.render_commands_rect,
        .clip => &self.render_commands_clip,
        .text => &self.render_commands_text,
    };
    self.render_commands.append(self.allocator, .init(Kind, cmdbuf.items.len)) catch |err|
        std.log.err("EmitRenderCommand({t}): {t}", .{ Kind, err });
    cmdbuf.append(self.allocator, payload) catch |err|
        std.log.err("EmitRenderCommand({t}): {t}", .{ Kind, err });
}

fn DoElementEmitRenderCommands(self: *GU) void {
    const sd = self.backend.SurfaceSize();
    const c_base = Rect{ .x = 0, .y = 0, .w = sd.x, .h = sd.y };
    var c = c_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (!e.area.IsCollidingRect(&c)) continue;

        // returning to parent from child, don't need to process anything more
        if (it_data.relation == .Parent) {
            c = if (e.parent) |p| self.element_tree.items[p].clip else c_base;
            self.EmitRenderCommand(.clip, RCClip{ .area = c });
            continue;
        }

        // this element is an unprocessed parent, so we go deeper
        defer if (e.first_child != null) {
            c = e.clip;
            self.EmitRenderCommand(.clip, RCClip{ .area = e.clip });
        };

        // is it actually drawable?
        if (Color.fromInt(e.layout.color).a == 0) continue;
        if (!e.area.AreaIsNonZero()) continue;

        if (e.features.bShowRect) {
            self.EmitRenderCommand(.rect, RCRect{
                .rect = e.area,
                .corner_radius = e.layout.corner_radius,
                .corner_shape = e.layout.corner_shape,
                .color = e.layout.color,
                .texture = e.texture,
                .tile = null,
            });
        }

        if (e.features.bCustomCommand) {
            assert(e.custom_action != maxInt(usize)); // non-null value actually set
            self.EmitRenderCommand(.custom, RCCustom{
                .action = e.custom_action,
                .rect = e.area,
                .corner_radius = e.layout.corner_radius,
                .corner_shape = e.layout.corner_shape,
                .color = e.layout.color,
            });
        }

        if (e.features.bShowLabel and e.label_str.len > 0) {
            // FIXME: need a way to ensure that the text gets drawn after (i.e.
            //  on top), because they will both be emitted at the same time
            //  and the renderer may not respect the call order if batching;
            //  maybe add a "batch layer" value to draw cmd, and give labels
            //  a half-value extra so that they are intereted as upper layer.
            self.EmitRenderCommand(.text, RCText{
                .pos = e.area.toPos(),
                .font = e.label_font,
                .color = e.layout.color,
                .str = e.label_str,
            });
        }
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

        btn.area = self.element_tree.items[btn.element].clip;
        btn.element = maxInt(usize);
    }

    while (self.button_delete_queue.pop()) |item|
        _ = self.buttons.remove(item);
}

fn DoElementDebugLog(self: *GU) void {
    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        std.log.debug(
            "it-element: ({*})  {t: <12}{d: >3}x{d: <3}",
            .{ e, it_data.relation, e.area.w, e.area.h },
        );
    }
}

//------------------------------------------------------------------------------
// LAYOUT

/// returns whether creating a new container was successful. guarantees the element
/// tree will be in a valid state (i.e. the same as before calling, on failure).
pub fn DoElement(self: *GU, layout: ?*const Layout) bool {
    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const element_i = self.element_tree.items.len; // next index will equal len

    const ld: *LineData = &self.element_line_stack.items[self.element_line_stack.items.len - 1];

    self.element_tree.append(self.allocator, e: {
        var e: Element = .empty;
        e.layout = if (layout) |lo| lo.* else .blank;
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

    // TODO: manage this elsewhere and make this a single function call, else
    //  the upcoming billion stacks will overrun this fn
    // process SetNext api
    self.font_vstk.PushDequeue(element_i);
    self.btn_mode_vstk.PushDequeue(element_i);
    self.btn_style_vstk_padding_ver.PushDequeue(element_i);
    self.btn_style_vstk_padding_hor.PushDequeue(element_i);
    self.btn_style_vstk_corner_rad.PushDequeue(element_i);
    self.btn_style_vstk_corner_shape.PushDequeue(element_i);
    self.btn_style_vstk_color_idle.PushDequeue(element_i);
    self.btn_style_vstk_color_hover.PushDequeue(element_i);
    self.btn_style_vstk_color_down.PushDequeue(element_i);

    const parent: ?*Element = if (parent_i) |i| &self.element_tree.items[i] else null;
    const element: *Element = &self.element_tree.items[element_i];

    if (self.element_queue_line_break or (parent != null and ld.current_items == parent.?.layout.widths.len)) {
        self.element_queue_line_break = false;
        ld.line += 1;
        ld.current_items = 0;
        element.features.bLineBreak = true;
    }
    ld.current_items += 1;

    if (parent) |pa| {
        if (pa.first_child == null) pa.first_child = element_i;
        if (pa.layout.widths.len > 0) {
            element.area.w = pa.layout.widths[(ld.current_items - 1) % pa.layout.widths.len];
            element.layout.mode_w = DimensionMode.ParseAuto(element.area.w);
        }
        if (pa.layout.heights.len > 0) {
            element.area.h = pa.layout.heights[(ld.line - 1) % pa.layout.heights.len];
            element.layout.mode_h = DimensionMode.ParseAuto(element.area.h);
        }
        pa.children += 1; // FIXME: now redundant with line break parsing implemented?
    }

    if (self.element_sibling) |sibling| {
        self.element_tree.items[sibling].sibling_next = element_i;
        self.element_sibling = null;
    }

    self.element_line_stack.append(self.allocator, zeroInit(LineData, .{ .line = 1 })) catch |err|
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

    // TODO: manage this elsewhere and make this a single function call, else
    //  the upcoming billion stacks will overrun this fn
    // process SetNext api
    defer {
        self.font_vstk.PopAuto(element_i);
        self.btn_mode_vstk.PopAuto(element_i);
        self.btn_style_vstk_padding_ver.PopAuto(element_i);
        self.btn_style_vstk_padding_hor.PopAuto(element_i);
        self.btn_style_vstk_corner_rad.PopAuto(element_i);
        self.btn_style_vstk_corner_shape.PopAuto(element_i);
        self.btn_style_vstk_color_idle.PopAuto(element_i);
        self.btn_style_vstk_color_hover.PopAuto(element_i);
        self.btn_style_vstk_color_down.PopAuto(element_i);
    }

    if (element.layout.mode_w == .Stretch) {
        assert(parent != null);
        assert(parent.?.layout.widths.len > 0);
        assert(parent.?.layout.mode_w.IsPreComputable());
        assert(element.area.w < 0);
    }
    if (element.layout.mode_h == .Stretch) {
        assert(parent != null);
        assert(parent.?.layout.heights.len > 0);
        assert(parent.?.layout.mode_h.IsPreComputable());
        assert(element.area.h < 0);
    }

    // Button
    if (element.features.bClickable) {
        // button state setup
        const btn: *const Button = btn: {
            const btn_key = self.GetElementKeyAt(element_i);
            const btn_info = self.buttons.getOrPut(btn_key) catch break :btn &.empty;

            const btn = btn_info.value_ptr;
            if (!btn_info.found_existing) btn.* = .empty;
            btn.element = element.id;
            btn.mode = self.btn_mode_vstk.GetOrNull() orelse .default;
            break :btn btn;
        };

        // visual updating
        if (!element.features.bClickNoStyle) {
            const btn_style = &self.btn_style_arena.items[self.ButtonStyleGet()];
            element.layout.color = switch (btn.state) {
                .Idle => if (element.features.bClickDepressed) btn_style.ColorDown else btn_style.ColorIdle,
                .Hover => if (element.features.bClickDepressed) btn_style.ColorIdle else btn_style.ColorHover,
                .Down => btn_style.ColorDown,
            };
            element.layout.padding = .{ .x = btn_style.PaddingHor, .y = btn_style.PaddingVer };
            element.layout.corner_radius = btn_style.CornerRad;
            element.layout.corner_shape = btn_style.CornerShape;
        }
    }

    // Texture: behaviour of sizing the element with relation to the texture (e.g.
    // "draw image = match texture size with fixed sizing") is left to the widget impl
    if (element.features.bShowTexture) {
        assert(element.features.bShowRect == true);
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
        const font = self.font_vstk.GetOrNull() orelse self.base_font;
        assert(element.features.bShowRect == false);
        //assert(element.label_str.len > 0);

        const label_size = &self.backend.StringSize(font, element.label_str);
        element.layout.mode_w = .Fixed;
        element.layout.mode_h = .Fixed;
        element.area.w = label_size.x;
        element.area.h = label_size.y;
        element.label_font = font;
    }

    // TODO: ?? have a "GetTextSpacing" backend function, to directly inform
    //  this, instead of measuring an actual space character?
    if (element.features.bTextSpacing) {
        const font = self.font_vstk.GetOrNull() orelse self.base_font;
        const space_size = &self.backend.StringSize(font, " ");
        element.layout.gaps.x = space_size.x;
    }
}

/// Returns pointer to the current element. Pointer is only guaranteed to be valid
/// until the next call to DoElement, including implicit calls in widget helpers.
pub inline fn GetElement(self: *GU) *Element {
    const i = self.element_stack.getLast();
    return &self.element_tree.items[i];
}

/// Returns pointer to the element associated with a given handle. Pointer is only
/// guaranteed to be valid until the next call to DoElement, including implicit
/// calls in widget helpers.
pub inline fn GetElementAt(self: *GU, i: usize) *Element {
    assert(self.element_tree.items.len > i);
    return &self.element_tree.items[i];
}

fn GetElementKey(self: *GU) []const u8 {
    return self.GetElement().HashKey();
}

fn GetElementKeyAt(self: *GU, i: usize) []const u8 {
    return self.GetElementAt(i).HashKey();
}

fn GetElementClicked(self: *GU) bool {
    const btn_key = self.GetElementKey();
    const btn: Button = self.buttons.get(btn_key) orelse .empty;
    return btn.activated;
}

fn GetElementClickedAt(self: *GU, i: usize) bool {
    const btn_key = self.GetElementKeyAt(i);
    const btn: Button = self.buttons.get(btn_key) orelse .empty;
    return btn.activated;
}

// FIXME: the following will need to be moved and possibly adjusted for the
//  push/pop/setnext api when the layout/style stacks are implemented
// TODO: re-evaluate whether a "Set" counterpart to the push/pop/setnext functions
//  is needed or practical

pub fn SetElementColor(self: *GU, color: u32) void {
    const element = self.GetElement();
    element.layout.color = color;
}

pub fn SetElementPadding(self: *GU, padding: Vec2) void {
    const element = self.GetElement();
    element.layout.padding = padding;
}

pub fn SetElementGaps(self: *GU, hor: f32, ver: f32) void {
    const element = self.GetElement();
    element.layout.gaps.x = hor;
    element.layout.gaps.y = ver;
}

pub fn SetElementSize(self: *GU, w: f32, h: f32) void {
    const element = self.GetElement();
    element.area.w = w;
    element.area.h = h;
}

//------------------------------------------------------------------------------
// STACKS

// TODO: testcase - bounds-checking using fixed buffer allocator
// TODO: ?? take mutable slice instead of allocator; require upfront memory. may
//  also make sense to impose limits on stack sizes on everything rather than
//  just throwing usize at it, since just storing usize IDs can take more memory
//  than the values and the number of values will never reach usize (nor close to)
// TODO: ?? use MultiArrayList with handles in GU struct to manage all the stacks
/// errorless value stacks. stack usage is reference-counted independently of
/// stack size, and pushing/popping is synchronized to this counter, such that
/// user code can always push/pop without worrying about error handling. in such
/// an error case, the actual value used will be the top value as usual, and the
/// developer is expected to identify this during development and tune the stack
/// capacity to their use case.
pub fn ValueStack(comptime ValueT: type) type {
    return struct {
        alloc: Allocator, // FIXME: drop the allocator, use slices exclusively
        count: usize,
        stack_values: ArrayList(ValueT),
        stack_pop_queue: ArrayList(QueueItem),
        stack_queued: bool,
        changed_since_check: bool,

        const ValueStackT = @This();

        pub const QueueItem = struct {
            id: usize,
            count: usize,
        };

        pub fn Init(alloc: Allocator) ValueStackT {
            return .{
                .alloc = alloc,
                .count = 0,
                .stack_values = .empty,
                .stack_pop_queue = .empty,
                .stack_queued = false,
                .changed_since_check = false,
            };
        }

        pub fn Deinit(self: *ValueStackT) void {
            self.stack_values.clearAndFree(self.alloc);
            self.stack_pop_queue.clearAndFree(self.alloc);
        }

        pub fn Reset(self: *ValueStackT) void {
            self.stack_values.clearRetainingCapacity();
            self.stack_pop_queue.clearRetainingCapacity();
            self.count = 0;
        }

        pub fn Get(self: *ValueStackT) ValueT {
            assert(self.stack_values.items.len > 0);
            return self.stack_values.getLast();
        }

        pub fn GetOrNull(self: *ValueStackT) ?ValueT {
            return self.stack_values.getLastOrNull();
        }

        pub fn CheckChanged(self: *ValueStackT) bool {
            defer self.changed_since_check = false;
            return self.changed_since_check;
        }

        // inline because intended to be wrapped by user-facing API fn
        pub inline fn Push(self: *ValueStackT, value: ValueT) void {
            assert(self.count >= self.stack_values.items.len);
            assert(self.stack_queued == false); // block against misusing stack
            defer self.count += 1;
            defer self.changed_since_check = true;

            self.stack_values.append(self.alloc, value) catch
                @panic("this is your sign to get around to using slices, idiot.");
        }

        // inline because intended to be wrapped by user-facing API fn
        pub inline fn Pop(self: *ValueStackT) void {
            assert(self.count >= self.stack_values.items.len);
            assert(self.count > 0);
            defer self.count -= 1;
            defer self.changed_since_check = true;

            if (self.stack_values.items.len == self.count)
                _ = self.stack_values.pop();
        }

        // inline because intended to be wrapped by user-facing API fn
        pub inline fn PushEnqueue(self: *ValueStackT, value: ValueT) void {
            self.Push(value);
            self.stack_queued = true;
        }

        pub fn PushDequeue(self: *ValueStackT, id: usize) void {
            if (!self.stack_queued) return;

            self.stack_queued = false;
            self.stack_pop_queue.append(self.alloc, QueueItem{
                .count = self.count,
                .id = id,
            }) catch @panic("this is your sign to get around to using slices, idiot.");
        }

        pub fn PopAuto(self: *ValueStackT, id: usize) void {
            const next = self.stack_pop_queue.getLastOrNull() orelse return;

            if (next.id != id) return;
            assert(next.count == self.count); // make sure user popped everything
            self.Pop();
            _ = self.stack_pop_queue.pop();
        }
    };
}

//--------------------------------------
// BUTTON STYLE

// FIXME: (button styles) the actual indexing of the arena could behave like a
//  stack, thereby avoiding unnecessary pushing of redundant styles, no?
// TODO: ?? use ValueStack for the ButtonStyle arena itself?

fn ButtonStyleStackStart(self: *GU) void {
    assert(self.ButtonStyleAllEmpty());
    self.PushButtonStyle(self.base_button_style);
    self.ButtonStyleGenerate();
}

fn ButtonStyleStackEnd(self: *GU) void {
    self.PopButtonStyle();
}

/// returns `btn_style_arena` index for current button style configuration.
fn ButtonStyleGet(self: *GU) usize {
    assert(self.btn_style_arena.items.len > 0);

    if (self.ButtonStyleAnyChanged())
        self.ButtonStyleGenerate();

    return self.btn_style_arena.items.len - 1;
}

// implicitly asserts all value stacks have at least one item via `Get`
fn ButtonStyleGenerate(self: *GU) void {
    self.btn_style_arena.append(self.allocator, ButtonStyle{
        .PaddingVer = self.btn_style_vstk_padding_ver.Get(),
        .PaddingHor = self.btn_style_vstk_padding_hor.Get(),
        .CornerRad = self.btn_style_vstk_corner_rad.Get(),
        .CornerShape = self.btn_style_vstk_corner_shape.Get(),
        .ColorIdle = self.btn_style_vstk_color_idle.Get(),
        .ColorHover = self.btn_style_vstk_color_hover.Get(),
        .ColorDown = self.btn_style_vstk_color_down.Get(),
    }) catch |e| std.log.err("(ButtonStyleGenerate) append failed: {t}", .{e});
}

fn ButtonStyleAnyChanged(self: *GU) bool {
    return @intFromBool(self.btn_style_vstk_padding_ver.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_padding_hor.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_corner_rad.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_corner_shape.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_color_idle.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_color_hover.CheckChanged()) |
        @intFromBool(self.btn_style_vstk_color_down.CheckChanged()) > 0;
}

fn ButtonStyleAllEmpty(self: *GU) bool {
    return @intFromBool(self.btn_style_arena.items.len == 0) &
        @intFromBool(self.btn_style_vstk_padding_ver.count == 0) &
        @intFromBool(self.btn_style_vstk_padding_hor.count == 0) &
        @intFromBool(self.btn_style_vstk_corner_rad.count == 0) &
        @intFromBool(self.btn_style_vstk_corner_shape.count == 0) &
        @intFromBool(self.btn_style_vstk_color_idle.count == 0) &
        @intFromBool(self.btn_style_vstk_color_hover.count == 0) &
        @intFromBool(self.btn_style_vstk_color_down.count == 0) > 0;
}

//------------------------------------------------------------------------------
// PUSH/POP/SETNEXT API

//--------------------------------------
// FONT

pub fn SetNextFont(self: *GU, font: FontHandle) void {
    self.font_vstk.PushEnqueue(font);
}

pub fn PushFont(self: *GU, font: FontHandle) void {
    self.font_vstk.Push(font);
}

pub fn PopFont(self: *GU) void {
    self.font_vstk.Pop();
}

//--------------------------------------
// BUTTON MODE

pub fn SetNextButtonMode(self: *GU, mode: ButtonMode) void {
    self.btn_mode_vstk.PushEnqueue(mode);
}

pub fn PushButtonMode(self: *GU, mode: ButtonMode) void {
    self.btn_mode_vstk.Push(mode);
}

pub fn PopButtonMode(self: *GU) void {
    self.btn_mode_vstk.Pop();
}

//--------------------------------------
// BUTTON STYLE

pub fn SetNextButtonStyle(self: *GU, style: ButtonStyle) void {
    self.SetNextButtonPaddingHorizontal(style.PaddingHor);
    self.SetNextButtonPaddingVertical(style.PaddingVer);
    self.SetNextButtonCornerRadius(style.CornerRad);
    self.SetNextButtonCornerShape(style.CornerShape);
    self.SetNextButtonColorIdle(style.ColorIdle);
    self.SetNextButtonColorHover(style.ColorHover);
    self.SetNextButtonColorDown(style.ColorDown);
}

pub fn SetNextButtonPadding(self: *GU, horizontal: f32, vertical: f32) void {
    self.SetNextButtonPaddingHorizontal(horizontal);
    self.SetNextButtonPaddingVertical(vertical);
}

pub fn SetNextButtonCorner(self: *GU, radius: f32, shape: CornerShape) void {
    self.SetNextButtonCornerRadius(radius);
    self.SetNextButtonCornerShape(shape);
}

pub fn SetNextButtonColor(self: *GU, idle: u32, hover: u32, down: u32) void {
    self.SetNextButtonColorIdle(idle);
    self.SetNextButtonColorHover(hover);
    self.SetNextButtonColorDown(down);
}

pub fn SetNextButtonPaddingHorizontal(self: *GU, value: f32) void {
    self.btn_style_vstk_padding_hor.PushEnqueue(value);
}

pub fn SetNextButtonPaddingVertical(self: *GU, value: f32) void {
    self.btn_style_vstk_padding_ver.PushEnqueue(value);
}

pub fn SetNextButtonCornerRadius(self: *GU, value: f32) void {
    self.btn_style_vstk_corner_rad.PushEnqueue(value);
}

pub fn SetNextButtonCornerShape(self: *GU, value: CornerShape) void {
    self.btn_style_vstk_corner_shape.PushEnqueue(value);
}

pub fn SetNextButtonColorIdle(self: *GU, value: u32) void {
    self.btn_style_vstk_color_idle.PushEnqueue(value);
}

pub fn SetNextButtonColorHover(self: *GU, value: u32) void {
    self.btn_style_vstk_color_hover.PushEnqueue(value);
}

pub fn SetNextButtonColorDown(self: *GU, value: u32) void {
    self.btn_style_vstk_color_down.PushEnqueue(value);
}

pub fn PushButtonStyle(self: *GU, style: ButtonStyle) void {
    self.PushButtonPaddingHorizontal(style.PaddingHor);
    self.PushButtonPaddingVertical(style.PaddingVer);
    self.PushButtonCornerRadius(style.CornerRad);
    self.PushButtonCornerShape(style.CornerShape);
    self.PushButtonColorIdle(style.ColorIdle);
    self.PushButtonColorHover(style.ColorHover);
    self.PushButtonColorDown(style.ColorDown);
}

pub fn PushButtonPadding(self: *GU, horizontal: f32, vertical: f32) void {
    self.PushButtonPaddingHorizontal(horizontal);
    self.PushButtonPaddingVertical(vertical);
}

pub fn PushButtonCorner(self: *GU, radius: f32, shape: CornerShape) void {
    self.PushButtonCornerRadius(radius);
    self.PushButtonCornerShape(shape);
}

pub fn PushButtonColor(self: *GU, idle: u32, hover: u32, down: u32) void {
    self.PushButtonColorIdle(idle);
    self.PushButtonColorHover(hover);
    self.PushButtonColorDown(down);
}

pub fn PushButtonPaddingHorizontal(self: *GU, value: f32) void {
    self.btn_style_vstk_padding_hor.Push(value);
}

pub fn PushButtonPaddingVertical(self: *GU, value: f32) void {
    self.btn_style_vstk_padding_ver.Push(value);
}

pub fn PushButtonCornerRadius(self: *GU, value: f32) void {
    self.btn_style_vstk_corner_rad.Push(value);
}

pub fn PushButtonCornerShape(self: *GU, value: CornerShape) void {
    self.btn_style_vstk_corner_shape.Push(value);
}

pub fn PushButtonColorIdle(self: *GU, value: u32) void {
    self.btn_style_vstk_color_idle.Push(value);
}

pub fn PushButtonColorHover(self: *GU, value: u32) void {
    self.btn_style_vstk_color_hover.Push(value);
}

pub fn PushButtonColorDown(self: *GU, value: u32) void {
    self.btn_style_vstk_color_down.Push(value);
}

pub fn PopButtonStyle(self: *GU) void {
    self.PopButtonPaddingHorizontal();
    self.PopButtonPaddingVertical();
    self.PopButtonCornerRadius();
    self.PopButtonCornerShape();
    self.PopButtonColorIdle();
    self.PopButtonColorHover();
    self.PopButtonColorDown();
}

pub fn PopButtonPadding(self: *GU) void {
    self.PopButtonPaddingHorizontal();
    self.PopButtonPaddingVertical();
}

pub fn PopButtonCorner(self: *GU) void {
    self.PopButtonCornerRadius();
    self.PopButtonCornerShape();
}

pub fn PopButtonColor(self: *GU) void {
    self.PopButtonColorIdle();
    self.PopButtonColorHover();
    self.PopButtonColorDown();
}

pub fn PopButtonPaddingHorizontal(self: *GU) void {
    self.btn_style_vstk_padding_hor.Pop();
}

pub fn PopButtonPaddingVertical(self: *GU) void {
    self.btn_style_vstk_padding_ver.Pop();
}

pub fn PopButtonCornerRadius(self: *GU) void {
    self.btn_style_vstk_corner_rad.Pop();
}

pub fn PopButtonCornerShape(self: *GU) void {
    self.btn_style_vstk_corner_shape.Pop();
}

pub fn PopButtonColorIdle(self: *GU) void {
    self.btn_style_vstk_color_idle.Pop();
}

pub fn PopButtonColorHover(self: *GU) void {
    self.btn_style_vstk_color_hover.Pop();
}

pub fn PopButtonColorDown(self: *GU) void {
    self.btn_style_vstk_color_down.Pop();
}

//------------------------------------------------------------------------------
// WIDGET API

/// format a string using the internal frame arena. guaranteed to succeed; returns
/// an empty string when allocation is not possible.
pub fn MakeString(self: *GU, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(self.label_arena.allocator(), fmt, args) catch &.{};
}

/// Emit a custom action associated with a region. Typical use cases are drawing
/// a rendered scene to a specific part of the UI, drawing data-driven contents
/// such as lines and graphs, etc.
pub fn DoCustomSurface(self: *GU, action: CustomActionHandle, w: f32, h: f32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bCustomCommand = true;
    element.custom_action = action;
    element.area.w = w;
    element.area.h = h;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    element.layout.color = 0xFFFFFFFF;
}

// TODO: stretch-like rect dimensions
pub fn DoRect(self: *GU, w: f32, h: f32, color: u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowRect = true;
    element.area.w = w;
    element.area.h = h;
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
    const texture_size = self.backend.TextureSize(texture).MULS(scale);
    element.area.w = texture_size.x;
    element.area.h = texture_size.y;
}

// FIXME: remove color as input, use color stack (note: comments like these should
//  also be interpreted as "implement layout/styling as stacks in general")
/// create an element rendering text. see `MakeString` for string formatting
/// using the internal frame arena memory.
pub fn DoLabel(self: *GU, color: ?u32, str: []const u8) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowLabel = true;
    element.label_str = str;
    element.layout.color = color orelse 0xFFFFFFFF;
}

// TODO: better way to resolve font that factors in the push queue state?
// TODO: ?? better way to get tabsize?
// TODO: ?? paragraph-aware line break behaviour that inserts spacing
// TODO: ?? emit '/' '\' '-' elements that consume pre- or post-gaps based on context?
/// splits a given utf8 string into "words" and emits them as a series of label
/// elements, to allow the layout engine to reflow multiline text
pub fn DoLabelsFromString(self: *GU, str: []const u8) void {
    const font = self.font_vstk.GetOrNull() orelse self.base_font;
    const size_sp = &self.backend.StringSize(font, " ");
    const size_tb = &self.backend.StringSize(font, "    ");
    const SplitChars = std.ascii.whitespace ++ "-/\\";

    const view = std.unicode.Utf8View.init(str) catch return;
    var it = view.iterator();
    var i: usize = 0;
    while (it.nextCodepoint()) |cp| {
        defer i = it.i;
        switch (cp) {
            ' ' => {
                self.DoSpacerH(size_sp.x, size_sp.y);
                continue;
            },
            '\t' => {
                self.DoSpacerH(size_tb.x, size_tb.y);
                continue;
            },
            '\r' => {
                if (std.mem.indexOfScalar(u8, it.peek(1), '\n')) |_| _ = it.nextCodepoint();
                self.DoLineBreak();
                continue;
            },
            '\n' => {
                self.DoLineBreak();
                continue;
            },
            std.ascii.control_code.vt,
            std.ascii.control_code.ff,
            => continue,
            '/', '\\', '-' => {},
            else => while (std.mem.indexOfNone(u8, it.peek(1), SplitChars)) |_| {
                _ = it.nextCodepoint();
            },
        }
        self.DoLabel(null, str[i..it.i]);
    }
}

/// horizontal spacing element that overrides gap between surrounding elements.
/// spacer is ignored if it falls on the end of a line.
pub fn DoSpacerH(self: *GU, w: f32, h: f32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bConsumeGapX = true;
    element.features.bConsumeNextGapX = true;
    element.features.bOverflowCollapseX = true;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    element.area.w = w;
    element.area.h = h;
}

/// returns whether button was 'activated' (pressed). see `MakeString` for string
/// formatting using the internal frame arena memory. uses `label` for the hashing
/// key; if a key collision occurs, use `DoButtonNamed`.
pub fn DoButton(self: *GU, label: []const u8) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bClickable = true;
    element.features.bShowRect = true;
    element.name = label;

    self.DoLabel(null, label);

    return self.GetElementClicked();
}

/// same as DoButton, but exposes `name` to allow for hash disambiguation
pub fn DoButtonNamed(self: *GU, label: []const u8, name: []const u8) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bClickable = true;
    element.features.bShowRect = true;
    element.name = name;

    self.DoLabel(null, label);

    return self.GetElementClicked();
}

/// same general behaviour as DoButton, but updates an 'active' bool for you.
/// if button is culled (due to not rendering, clip culling, etc.), the external
/// bool will NOT be toggled. uses `label` for the hashing key; if a key collision
/// occurs, use `DoToggleButtonNamed`.
/// returns whether button was 'activated' (pressed and subsequently toggled). see
/// `MakeString` for string formatting using the internal frame arena memory.
pub fn DoToggleButton(self: *GU, active: *bool, label: []const u8) bool {
    return self.DoToggleButtonNamed(active, label, label);
}

/// same as DoToggleButton, but exposes `name` to allow for hash disambiguation
pub fn DoToggleButtonNamed(self: *GU, active: *bool, label: []const u8, name: []const u8) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bClickable = true;
    element.features.bShowRect = true;
    element.name = name;
    element.data = @intFromPtr(active);

    const activated = self.GetElementClicked();
    if (active.*) element.features.bClickDepressed = true;
    if (activated) active.* = !active.*;

    self.DoLabel(null, label);

    return activated;
}

// FIXME: rename to something like "line clear", to reflect the fact that it doesn't
//  actually push the content down beyond ensuring the next element is at line start
pub fn DoLineBreak(self: *GU) void {
    self.element_queue_line_break = true;
}
