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

const GUMath = @import("gu_math.zig");
const GURect = GUMath.Rect;
const GUSize = GUMath.Size;
const GUPos = GUMath.Pos;
const GUColor = GUMath.Color;

pub const GUBackend = struct {
    ptr: *anyopaque,
    fnGetSurfaceDimensions: *const fn (*anyopaque) GUSize,
    fnDrawRect: *const fn (*anyopaque, *const GURenderCommand.Rect) void,
    fnDrawString: *const fn (*anyopaque, *const GURenderCommand.Text) void,
    fnDrawImage: *const fn (*anyopaque, *const GURenderCommand.Image) void,
    fnSetClip: *const fn (*anyopaque, *const GURenderCommand.Clip) void,
    fnBeginRendering: *const fn (*anyopaque) void,
    fnEndRendering: *const fn (*anyopaque) void,

    pub fn GetSurfaceDimensions(self: *GUBackend) GUSize {
        return self.fnGetSurfaceDimensions(self.ptr);
    }

    pub fn DrawRect(self: *GUBackend, cmd: *const GURenderCommand.Rect) void {
        self.fnDrawRect(self.ptr, cmd);
    }

    pub fn DrawString(self: *GUBackend, cmd: *const GURenderCommand.Text) void {
        self.fnDrawString(self.ptr, cmd);
    }

    // TODO: impl tile drawing, see GURenderCommand->Image
    pub fn DrawImage(self: *GUBackend, cmd: *const GURenderCommand.Image) void {
        self.fnDrawImage(self.ptr, cmd);
    }

    pub fn SetClip(self: *GUBackend, cmd: *const GURenderCommand.Clip) void {
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

pub const GUCorner = struct {
    radius: f32,
    style: Style,

    pub const Style = enum { None, Round, Custom1, Custom2, Custom3, Custom4, Custom5, Custom6 };
};

// FIXME: don't really like having the field types separated, but afaik needed to
// pass their types to function params (see GUBackend); investigate to confirm
// that it's actually not possible/practical to reference the field type directly
// WARN: also, not sure it's necessarily a good idea to obfuscate the field members
// when calling the GUBackend functions; however, it makes for cleaner fn defs
// and theoretically cuts down on stack thrashing (to compare/confirm), need to
// make a final call on which way to do it
pub const GURenderCommand = union(enum) {
    rect: Rect,
    text: Text,
    image: Image,
    clip: Clip,

    pub const Rect = struct {
        rect: GURect,
        corner: GUCorner,
        color: u32,
    };

    pub const Text = struct {
        str: []const u8,
        font: *GUFontAtlas,
        pos: GUPos,
        color: u32,
    };

    pub const Image = struct {
        image: *GUTextureAtlas,
        tile: ?u32, // for texture atlases
        pos: GUPos,
        color: u32,
    };

    pub const Clip = struct {
        area: GURect,
    };
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

pub const Button = struct {
    mode: Mode = .Press,
    state: State = .Idle,
    area: GURect,
    element: usize,

    pub const Mode = enum { Press, Release };
    pub const State = enum { Idle, Hover, Down };

    const PADDING_VERTICAL: f32 = 2;
    const PADDING_HORIZONTAL: f32 = 8;
    const CORNER_RADIUS: f32 = 6;
    const COLOR_IDLE: u32 = 0x008000FF;
    const COLOR_HOVER: u32 = 0x00C000FF;
    const COLOR_DOWN: u32 = 0x004000FF;

    pub fn Update(
        self: *Button,
        pt: *const GUPos,
        btn_just_down: bool,
        btn_just_up: bool,
    ) bool {
        if (self.area.IsCollidingPoint(pt)) {
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

// NOTE: keep here, intended as a 'using button api' struct, not part of the button api
const GUButtonData = struct { button: *Button, activated: bool };

pub const GUKeyState = struct {
    down: bool = false,
    just_up: bool = false,
    just_down: bool = false,
    accumulator_down: bool = false,
    accumulator_changes: u32 = 0,

    pub fn Accumulate(self: *GUKeyState, down: bool) void {
        if (self.accumulator_down != down) {
            self.accumulator_down = down;
            self.accumulator_changes += 1;
        }
    }

    pub fn Update(self: *GUKeyState) void {
        self.just_down = (self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.just_up = (!self.accumulator_down and self.accumulator_down != self.down) or
            self.accumulator_changes > 1;
        self.down = self.accumulator_down;
        self.accumulator_changes = 0;
    }
};

// TODO: impl image tilesets
// TODO: impl absolute/relative positioning
const Element = struct {
    id: usize,
    parent: ?usize,
    children: usize,
    first_child: ?usize,
    sibling_next: ?usize,
    sibling_prev: ?usize,

    mode: enum {
        /// don't do any special behaviours
        Block,
        Image, // FIXME: stuff based on Image should just be a "use texture"
        //         behaviour, where the `DoImage` just sets the dimensions of
        //         the element to match the texture.
        Label,
    },
    features: Features,
    layout: GULayout,
    area: GURect,
    fill: GUSize, // how big the element is for layout calculations
    image: GUImageHandle,
    label_str: []const u8,
    label_font: GUFontHandle,
    rect_size: GUSize,
    btn_state: Button.State,

    const empty: Element = .{
        .layout = .Default,
        .area = .Zero,
        .fill = .Zero,
        .mode = .Block,
        .id = 0,
        .parent = null,
        .children = 0,
        .first_child = null,
        .sibling_next = null,
        .sibling_prev = null,
        .features = .none,
        .image = maxInt(usize),
        .label_str = &.{},
        .label_font = maxInt(usize),
        .rect_size = .Zero,
        .btn_state = .Idle,
    };

    const Features = packed struct(u32) {
        // Visual functionality
        bShowRect: bool,
        bShowImage: bool, // assert image value set and bShowRect true
        bShowLabel: bool, // assert string and font value set
        // Layout functionality
        bLineBreak: bool,
        // Button functionality
        bClickable: bool,
        bClickDown: bool,
        bClickHover: bool,
        bClickDepressed: bool, // button visually "idles" in down-state

        _: u24,

        pub const none = std.mem.zeroInit(Features, .{});
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

    inline fn IsPreComputable(mode: GUDimensionMode) bool {
        return mode == .Fixed or mode == .Stretch;
    }
};

pub const GULayout = struct {
    mode_w: GUDimensionMode, // derived from parent 'widths' field if .Auto
    mode_h: GUDimensionMode, // derived from parent 'heights' field if .Auto
    color: u32,
    corner: GUCorner,
    widths: ?[]const f32,
    heights: ?[]const f32,
    padding: GUSize,
    gaps: GUSize,
    auto_line_break: bool,
    //scroll: ?

    const Default = zeroInit(GULayout, .{
        .auto_line_break = true,
    });
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

    // TODO: impl axis def in GULayout and derive
    pub inline fn AxisSpacing(self: *GULineData, comptime axis: enum { Main, Cross }, items: usize) f32 {
        const padding: f32, const gaps: f32 = switch (axis) {
            .Main => .{ // x-axis
                self.parent_padding.w * 2,
                self.parent_gaps.w * @as(f32, @floatFromInt(items -| 1)),
            },
            .Cross => .{ // y-axis
                self.parent_padding.h * 2,
                self.parent_gaps.h * @as(f32, @floatFromInt(items -| 1)),
            },
        };
        return padding + gaps;
    }
};

const GUImageHandle = usize;
const GUFontHandle = usize;

//------------------------------------------------------------------------------

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles, update GUFontHandle
images: ArrayList(GUTextureAtlas), // TODO: impl with handles, update GUImageHandle

element_tree: ArrayList(Element),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling
element_queue_line_break: bool,
element_line_stack: ArrayList(GULineData),

clip_stack: ArrayList(GURect),
label_arena: ArenaAllocator,

buttons: StringHashMap(Button),
button_delete_queue: ArrayList([]const u8),

base_layout: GULayout,

render_commands: ArrayList(GURenderCommand),

mouse_pt: GUPos,
mouse_left: GUKeyState, // LMB

pub fn Init(alloc: Allocator, backend: GUBackend, base_layout: ?GULayout) GU {
    return zeroInit(GU, .{
        .allocator = alloc,
        .label_arena = ArenaAllocator.init(alloc),
        .backend = backend,
        .fonts = ArrayList(GUFontAtlas).empty,
        .images = ArrayList(GUTextureAtlas).empty,
        .element_tree = ArrayList(Element).empty,
        .element_stack = ArrayList(usize).empty,
        .element_line_stack = ArrayList(GULineData).empty,
        .clip_stack = ArrayList(GURect).empty,
        .buttons = StringHashMap(Button).init(alloc),
        .button_delete_queue = ArrayList([]const u8).empty,
        .render_commands = ArrayList(GURenderCommand).empty,
        .base_layout = base_layout orelse GULayout.Default,
        .mouse_pt = .{ .x = -1, .y = -1 },
    });
}

pub fn Deinit(self: *GU) void {
    self.label_arena.deinit();
    self.render_commands.deinit(self.allocator);
    self.clip_stack.deinit(self.allocator);
    self.element_line_stack.deinit(self.allocator);
    self.element_stack.deinit(self.allocator);
    self.element_tree.deinit(self.allocator);
    self.images.deinit(self.allocator);
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
pub fn AddImage(self: *GU, image: GUTextureAtlas) !usize {
    try self.images.append(self.allocator, image);
    return self.images.items.len - 1;
}

//------------------------------------------------------------------------------
// FRAME

pub fn BeginFrame(self: *GU) !void {
    const surface_size = self.backend.GetSurfaceDimensions();

    assert(self.element_stack.items.len == 0);
    assert(self.element_line_stack.items.len == 0);
    _ = self.label_arena.reset(.retain_capacity);
    self.render_commands.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    self.element_line_stack.append(self.allocator, zeroInit(GULineData, .{ .line = 1 })) catch unreachable;
    if (!self.DoElement(&self.base_layout)) unreachable;
    const element = self.GetElement();
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    element.area.w = surface_size.w;
    element.area.h = surface_size.h;
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

    for (self.render_commands.items) |command| {
        switch (command) {
            .rect => |*rect| self.backend.DrawRect(rect),
            .text => |*text| self.backend.DrawString(text),
            .image => |*img| self.backend.DrawImage(img),
            .clip => |*clip| self.backend.SetClip(clip),
        }
    }

    self.backend.EndRendering();
}

//------------------------------------------------------------------------------
// LAYOUT PASSES

// FIXME: cleanup/streamline, maybe split into multiple passes if that makes sense
// TODO: rename to DoElementResizeAndParseLineBreaks ??
// TODO: update for text wrapping; will need to assert no padding/gaps, and remove
// .Fixed assertion for .Label in EndContainer
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
            ld.current_w + ld.parent_gaps.w + e.area.w > p.?.area.w - ld.parent_padding.w * 2)
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
            e.area.x = p.?.area.x + p.?.layout.padding.w;
            e.area.y = p.?.area.y + p.?.layout.padding.h;
            ld.current_y = e.area.y;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        const gaps = if (p != null) p.?.layout.gaps else GUSize.Zero;

        if (e.features.bLineBreak) {
            const pos = if (p != null) GUPos.FromRect(&p.?.area) else GUPos.Zero;
            const padding = if (p != null) p.?.layout.padding else GUSize.Zero;
            e.area.x = pos.x + padding.w;
            e.area.y = ld.current_y + ld.current_h + gaps.h;
            ld.current_y = e.area.y;
            ld.current_h = e.area.h;
        } else {
            const area = if (e.sibling_prev) |s| self.element_tree.items[s].area else GURect.Zero;
            e.area.x = area.x + area.w + gaps.w;
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
    const c_base = GURect{ .x = 0, .y = 0, .w = sd.w, .h = sd.h };
    self.render_commands.append(self.allocator, .{ .clip = .{ .area = c_base } }) catch |err|
        std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
    var c: *const GURect = &c_base;

    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (!e.area.IsCollidingRect(c)) continue;

        if (it_data.relation == .Parent) {
            _ = stack.pop();
            c = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &c_base;
            self.render_commands.append(self.allocator, .{ .clip = .{ .area = c.* } }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            continue;
        }

        // FIXME: add bEnableClipping element feature and refer to it here
        defer if (it_data.relation != .Parent and e.first_child != null) {
            stack.append(self.allocator, e.area.GetIntersection(c)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Clip Stack ({s})", .{@errorName(err)});
            c = &stack.items[stack.items.len - 1];
            self.render_commands.append(self.allocator, .{ .clip = .{ .area = c.* } }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
        };

        // is it actually drawable?
        if (GUColor.FromInt(e.layout.color).a == 0) continue;
        if (!e.area.HasNonZeroArea()) continue;

        switch (e.mode) {
            .Label => {
                // WARN: currently, the background is simply ignored because
                //  elements are modal, but this will not be true once the mode
                //  refactor is done. need to make a call on whether to ignore
                //  bg in presence of label, or stop conflating their values.
                // WARN: once this is fully separated from the background logic,
                //  will need a way to ensure that the text gets drawn after (i.e.
                //  on top), because they will both be emitted at the same time
                //  and the renderer may not respect the call order if batching;
                //  maybe add a "batch layer" value to draw cmd, and give labels
                //  a half-value extra so that they are intereted as upper layer.
                assert(e.label_str.len > 0);
                assert(e.label_font != maxInt(usize)); // TODO: proper/safe "null font" value
                self.render_commands.append(self.allocator, GURenderCommand{ .text = .{
                    .pos = GUPos.FromRect(&e.area),
                    .font = &self.fonts.items[e.label_font],
                    .color = e.layout.color,
                    .str = e.label_str,
                } }) catch |err| std.log.err(
                    "DoElementEmitDrawCommands: Draw Command ({s})",
                    .{@errorName(err)},
                );
            },
            .Image => {
                // FIXME: integrate with "ShowRect" path, such that "images" are
                //  simply textured rects (also: possibly adjust "image" naming
                //  internally to reflect this)
                assert(e.image != maxInt(usize)); // TODO: proper/safe "null image" value
                self.render_commands.append(self.allocator, GURenderCommand{ .image = .{
                    .pos = GUPos.FromRect(&e.area),
                    .image = &self.images.items[e.image],
                    .color = e.layout.color,
                    .tile = null,
                } }) catch |err| std.log.err(
                    "DoElementEmitDrawCommands: Draw Command ({s})",
                    .{@errorName(err)},
                );
            },
            .Block => {},
        }

        // replacement for Rect/Block paths; will also integrate old Image code
        // at some point
        if (e.features.bShowRect) {
            self.render_commands.append(self.allocator, GURenderCommand{
                .rect = .{
                    .rect = e.area,
                    .corner = e.layout.corner,
                    .color = e.layout.color,
                },
            }) catch |err| std.log.err(
                "DoElementEmitDrawCommands: Draw Command ({s})",
                .{@errorName(err)},
            );
        }
    }
}

fn DoElementDebugLog(self: *GU) void {
    var it = ElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;
        std.log.debug(
            "it-element: ({*})  {t: <12}{t: <10}{d}x{d}",
            .{ e, it_data.relation, e.mode, e.area.w, e.area.h },
        );
    }
}

fn DoButtonPostProcessing(self: *GU) void {
    assert(self.button_delete_queue.items.len == 0);

    var it = self.buttons.iterator();
    while (it.next()) |btn_info| {
        const btn = btn_info.value_ptr;
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
pub fn DoContainer(self: *GU, layout: ?*const GULayout) bool {
    if (layout) |lo| {
        if (lo.widths) |w| assert(w.len > 0);
        if (lo.heights) |h| assert(h.len > 0);
    }

    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const element_i = self.element_tree.items.len; // next index will equal len

    const ld: *GULineData = &self.element_line_stack.items[self.element_line_stack.items.len - 1];

    self.element_tree.append(self.allocator, e: {
        var e: Element = .empty;
        e.layout = if (layout) |lo| lo.* else .Default;
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
        std.debug.panic("DoContainer: ({s})", .{@errorName(err)});
    return true;
}

pub fn EndContainer(self: *GU) void {
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

    // TODO: move button style to a style stack-like setup, not hardcoded
    // Button
    if (element.features.bClickable) {
        element.layout.color = switch (element.btn_state) {
            .Idle => if (element.features.bClickDepressed) Button.COLOR_DOWN else Button.COLOR_IDLE,
            .Hover => if (element.features.bClickDepressed) Button.COLOR_IDLE else Button.COLOR_HOVER,
            .Down => Button.COLOR_DOWN,
        };
        element.layout.padding = .{ .w = Button.PADDING_HORIZONTAL, .h = Button.PADDING_VERTICAL };
        element.layout.corner = .{ .radius = Button.CORNER_RADIUS, .style = .Round };
    }

    switch (element.mode) {
        .Block => {},
        .Image => {
            assert(element.image != maxInt(usize)); // TODO: proper/safe "null font" value
            const image_size = &self.images.items[element.image].Size();
            element.area.w = image_size.w;
            element.area.h = image_size.h;
        },
        .Label => {
            assert(element.label_str.len > 0);
            assert(element.label_font != maxInt(usize)); // TODO: proper/safe "null font" value
            // TODO: account for text wrapping
            const label_size = &self.fonts.items[element.label_font].StringSize(element.label_str);
            element.area.w = label_size.w;
            element.area.h = label_size.h;
        },
    }
}

/// returns pointer to current element. pointer is only guaranteed to be valid
/// until the next call to DoContainer
pub inline fn GetContainer(self: *GU) *Element {
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

//------------------------------------------------------------------------------
// "STOCK" WIDGETS

// TODO: stretch-like rect dimensions
pub fn DoRect(self: *GU, size: GUSize, color: u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.area.w = size.w;
    element.area.h = size.h;
    element.layout.color = color;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
    element.features.bShowRect = true;
}

pub fn DoImage(self: *GU, image: GUImageHandle, color: ?u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .Image;
    element.image = image;
    element.layout.color = color orelse 0xFFFFFFFF;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
}

// TODO: add formatting, like standard string formatting functions
pub fn DoLabel(self: *GU, font: ?GUFontHandle, color: ?u32, comptime fmt: []const u8, args: anytype) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    const str = std.fmt.allocPrint(self.label_arena.allocator(), fmt, args) catch |err|
        std.debug.panic("DoLabel failed to allocate string: ({s})", .{@errorName(err)});
    element.mode = .Label;
    element.label_font = font orelse 0;
    element.label_str = str;
    element.layout.color = color orelse 0xFFFFFFFF;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
}

// TODO: more robust hashing strategy that doesn't cause hover state to break on
//  buttons that change where the button is in the element tree (e.g. by inserting
//  or removing an element above the button)
/// Turns the current element into a button and evaluates the input state. To
/// track state between frames, the button is identified internally by hash of the
/// element id concatenated with str. To emulate standard button behaviour in a
/// custom widget, refer to the call to this function in `DoButton`.
pub fn DoButtonLogic(self: *GU, mode: Button.Mode, str: []const u8) ?GUButtonData {
    const element = self.GetElement();
    element.features.bClickable = true;

    const btn: *Button = get_button: {
        const btn_key = std.fmt.allocPrint(self.allocator, "{X:0>16}{s}", .{ element.id, str }) catch
            return null;
        const btn_info = self.buttons.getOrPut(btn_key) catch
            return null;

        const btn = btn_info.value_ptr;
        if (!btn_info.found_existing) {
            btn.* = Button{
                .state = .Idle,
                .mode = mode,
                .area = .Zero,
                .element = element.id,
            };
        } else btn.element = element.id;

        element.btn_state = btn.state;
        break :get_button btn;
    };

    const activated = btn.Update(
        &self.mouse_pt,
        self.mouse_left.just_down,
        self.mouse_left.just_up,
    );

    return GUButtonData{ .button = btn, .activated = activated };
}

// NOTE: id hash uses input fmt, not resolved formatted string
/// returns whether button was 'activated' (pressed)
pub fn DoButton(self: *GU, font: ?GUFontHandle, comptime fmt: []const u8, args: anytype) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowRect = true;

    const btn = self.DoButtonLogic(.Press, fmt) orelse return false;

    self.DoLabel(font, null, fmt, args);

    return btn.activated;
}

// NOTE: id hash uses input fmt, not resolved formatted string
/// same general behaviour as DoButton, but updates an 'active' bool for you.
/// if button is culled (due to not rendering, clip culling, etc.), the external
/// bool will NOT be toggled
/// returns whether button was 'activated' (pressed and subsequently toggled)
pub fn DoToggleButton(self: *GU, active: *bool, font: ?GUFontHandle, comptime fmt: []const u8, args: anytype) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();
    element.features.bShowRect = true;

    const btn = self.DoButtonLogic(.Press, fmt) orelse return false;
    if (active.*) self.GetElement().features.bClickDepressed = true;
    if (btn.activated) active.* = !active.*;

    self.DoLabel(font, null, fmt, args);

    return btn.activated;
}

pub fn DoLineBreak(self: *GU) void {
    self.element_queue_line_break = true;
}
