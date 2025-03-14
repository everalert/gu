const GU = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const FormatOptions = std.fmt.FormatOptions;
const maxInt = std.math.maxInt;
const zeroInit = std.mem.zeroInit;

pub const GURect = struct {
    pub const Zero = GURect{ .x = 0, .y = 0, .w = 0, .h = 0 };
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn IsCollidingPoint(self: *const GURect, pt: *const GUPos) bool {
        return (pt.x >= self.x and
            pt.x < self.x + self.w and
            pt.y >= self.y and
            pt.y < self.y + self.h);
    }

    pub fn IsCollidingRect(self: *const GURect, other: *const GURect) bool {
        return (self.x + self.w >= other.x and
            self.x <= other.x + other.w and
            self.y + self.h >= other.y and
            self.y <= other.y + other.h);
    }

    /// AND operation
    pub fn GetIntersection(r1: *const GURect, r2: *const GURect) GURect {
        const x = @max(r1.x, r2.x);
        const y = @max(r1.y, r2.y);
        const w = @min(r1.x + r1.w, r2.x + r2.w) - x;
        const h = @min(r1.y + r1.h, r2.y + r2.h) - y;
        return GURect{ .x = x, .y = y, .w = w, .h = h };
    }

    /// compatibility with std.fmt
    pub fn format(self: *const GURect, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        try writer.print(
            "GURect(x:{d: <4} y:{d: <4} w:{d: <4} h:{d: <4})",
            .{ self.x, self.y, self.w, self.h },
        );
    }
};

// TODO: rename to GUPoint?
pub const GUPos = struct {
    pub const Zero = GUPos{ .x = 0, .y = 0 };
    x: f32,
    y: f32,

    pub fn FromRect(rect: *GURect) GUPos {
        return GUPos{ .x = rect.x, .y = rect.y };
    }
};

pub const GUSize = struct {
    pub const Zero = GUSize{ .w = 0, .h = 0 };
    w: f32,
    h: f32,

    pub fn FromRect(rect: *GURect) GUSize {
        return GUSize{ .w = rect.w, .h = rect.h };
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
    fnSetClip: *const fn (*anyopaque, *const GURect) void,
    fnBeginRendering: *const fn (*anyopaque) void,
    fnEndRendering: *const fn (*anyopaque) void,

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

    pub fn SetClip(self: *GUBackend, area: *const GURect) void {
        self.fnSetClip(self.ptr, area);
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
    Clip: struct {
        area: GURect,
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

const GUButtonMode = enum(u32) { Press, Release };
const GUButtonState = enum(u32) { Idle, Hover, Down };
pub const GUButton = struct {
    const PADDING_VERTICAL: f32 = 2;
    const PADDING_HORIZONTAL: f32 = 8;
    const COLOR_IDLE: u32 = 0x008000FF;
    const COLOR_HOVER: u32 = 0x00C000FF;
    const COLOR_DOWN: u32 = 0x004000FF;

    mode: GUButtonMode = .Press,
    state: GUButtonState = .Idle,
    area: GURect,
    element: usize,

    pub fn Update(
        self: *GUButton,
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
const GUButtonData = struct { button: *GUButton, activated: bool };

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
const GUElement = struct {
    layout: GULayout,
    area: GURect,
    fill: GUSize, // how big the element is for layout calculations
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

const GUDimensionMode = enum(u32) {
    Auto, // Fit when parent does not specify dimension, or 0=Fit, <0=Stretch, >0=Fixed
    Fit, // child dimensions plus any margins, etc.
    Stretch, // usable space of parent dimension minus input value; requires pre-finalizable parent dimension
    Fixed,

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

allocator: Allocator,

backend: GUBackend,

fonts: ArrayList(GUFontAtlas), // TODO: impl with handles, update GUFontHandle
images: ArrayList(GUTextureAtlas), // TODO: impl with handles, update GUImageHandle

element_tree: ArrayList(GUElement),
element_stack: ArrayList(usize),
element_sibling: ?usize, // most recent sibling
element_queue_line_break: bool,
element_line_stack: ArrayList(GULineData),

clip_stack: ArrayList(GURect),
label_arena: ArenaAllocator,

buttons: StringHashMap(GUButton),
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
        .fonts = ArrayList(GUFontAtlas).init(alloc),
        .images = ArrayList(GUTextureAtlas).init(alloc),
        .element_tree = ArrayList(GUElement).init(alloc),
        .element_stack = ArrayList(usize).init(alloc),
        .element_line_stack = ArrayList(GULineData).init(alloc),
        .clip_stack = ArrayList(GURect).init(alloc),
        .buttons = StringHashMap(GUButton).init(alloc),
        .button_delete_queue = ArrayList([]const u8).init(alloc),
        .render_commands = ArrayList(GURenderCommand).init(alloc),
        .base_layout = base_layout orelse GULayout.Default,
        .mouse_pt = .{ .x = -1, .y = -1 },
    });
}

pub fn Deinit(self: *GU) void {
    self.label_arena.deinit();
    self.render_commands.deinit();
    self.clip_stack.deinit();
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
    _ = self.label_arena.reset(.retain_capacity);
    self.render_commands.clearRetainingCapacity();
    self.element_tree.clearRetainingCapacity();
    self.element_sibling = null;
    self.mouse_left.Update();

    self.element_line_stack.append(zeroInit(GULineData, .{ .line = 1 })) catch unreachable;
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
            .Rect => |rect| self.backend.DrawRect(&rect.rect, rect.color),
            .Text => |text| self.backend.DrawString(text.font, &text.pos, text.str, text.color),
            .Image => |img| self.backend.DrawImage(img.image, &img.pos, img.color),
            .Clip => |clip| self.backend.SetClip(&clip.area),
        }
    }

    self.backend.EndRendering();
}

// FIXME: cleanup/streamline, maybe split into multiple passes if that makes sense
// TODO: rename to DoElementResizeAndParseLineBreaks ??
// TODO: update for text wrapping; will need to assert no padding/gaps, and remove
// .Fixed assertion for .Label in EndContainer
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
        const p: ?*GUElement = if (e.parent) |pa_i| &self.element_tree.items[pa_i] else null;

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
            e.line_break = true;

        if (it_data.relation == .Child or e.line_break) {
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
            stack.appendAssumeCapacity(zeroInit(GULineData, .{})); // capacity set during initial tree gen
            ld = &stack.items[stack.items.len - 1];
            e.area.x = p.?.area.x + p.?.layout.padding.w;
            e.area.y = p.?.area.y + p.?.layout.padding.h;
            ld.current_y = e.area.y;
            ld.current_h = @max(ld.current_h, e.area.h);
            continue;
        }

        const gaps = if (p != null) p.?.layout.gaps else GUSize.Zero;

        if (e.line_break) {
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
    std.debug.assert(self.element_stack.items.len == 0);
    std.debug.assert(self.clip_stack.items.len == 0);
    defer std.debug.assert(self.element_stack.items.len == 0);
    defer std.debug.assert(self.clip_stack.items.len == 0);

    const stack = &self.clip_stack;
    const sd = self.backend.GetSurfaceDimensions();
    const c_base = GURect{ .x = 0, .y = 0, .w = sd.w, .h = sd.h };
    self.render_commands.append(.{ .Clip = .{ .area = c_base } }) catch |err|
        std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
    var c: *const GURect = &c_base;

    var it = GUElementIterator.Init(self.element_tree.items);
    while (it.Next()) |it_data| {
        const e = it_data.element;

        if (!e.area.IsCollidingRect(c)) continue;

        if (it_data.relation == .Parent) {
            _ = stack.pop();
            c = if (stack.items.len > 0) &stack.items[stack.items.len - 1] else &c_base;
            self.render_commands.append(.{ .Clip = .{ .area = c.* } }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
            continue;
        }

        defer if (it_data.relation != .Parent and e.first_child != null) {
            stack.append(e.area.GetIntersection(c)) catch |err|
                std.log.err("DoElementEmitDrawCommands: Clip Stack ({s})", .{@errorName(err)});
            c = &stack.items[stack.items.len - 1];
            self.render_commands.append(.{ .Clip = .{ .area = c.* } }) catch |err|
                std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
        };

        if (GUColor.FromInt(e.layout.color).a == 0) continue;

        self.render_commands.append(switch (e.mode) {
            .Label => |label| .{ .Text = .{
                .pos = GUPos.FromRect(&e.area),
                .font = &self.fonts.items[label.font],
                .color = e.layout.color,
                .str = label.str,
            } },
            .Image => |img| .{ .Image = .{
                .pos = GUPos.FromRect(&e.area),
                .image = &self.images.items[img.image],
                .color = e.layout.color,
                .tile = null,
            } },
            .Rect, .Button, .Block => .{ .Rect = .{
                .rect = e.area,
                .color = e.layout.color,
            } },
        }) catch |err| std.log.err("DoElementEmitDrawCommands: Draw Command ({s})", .{@errorName(err)});
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
    if (layout) |lo| {
        if (lo.widths) |w| std.debug.assert(w.len > 0);
        if (lo.heights) |h| std.debug.assert(h.len > 0);
    }

    const parent_i: ?usize = self.element_stack.getLastOrNull();
    const element_i = self.element_tree.items.len; // next index will equal len

    const ld: *GULineData = &self.element_line_stack.items[self.element_line_stack.items.len - 1];

    self.element_tree.append(GUElement{
        .area = GURect.Zero,
        .fill = GUSize.Zero,
        .layout = if (layout) |lo| lo.* else GULayout.Default,
        .mode = .{ .Block = {} },
        .id = element_i,
        .parent = parent_i,
        .sibling_next = null,
        .sibling_prev = self.element_sibling,
        .children = 0,
        .first_child = null,
        .line_break = false,
    }) catch return false;

    self.element_stack.append(element_i) catch {
        _ = self.element_tree.pop();
        return false;
    };

    const parent: ?*GUElement = if (parent_i) |i| &self.element_tree.items[i] else null;
    const element: *GUElement = &self.element_tree.items[element_i];

    if (self.element_queue_line_break or
        (parent != null and parent.?.layout.widths != null and
        ld.current_items == parent.?.layout.widths.?.len))
    {
        self.element_queue_line_break = false;
        ld.line += 1;
        ld.current_items = 0;
        element.line_break = true;
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

    self.element_line_stack.append(zeroInit(GULineData, .{ .line = 1 })) catch |err|
        std.debug.panic("DoContainer: ({s})", .{@errorName(err)});
    return true;
}

pub fn EndContainer(self: *GU) void {
    _ = self.element_line_stack.pop();
    const element_i = self.element_stack.pop();
    const element: *GUElement = &self.element_tree.items[element_i];
    const parent: ?*GUElement = if (element.parent) |p| &self.element_tree.items[p] else null;
    self.element_sibling = element_i;
    self.element_queue_line_break = false; // cleanup unused line break

    if (element.layout.mode_w == .Stretch) {
        std.debug.assert(parent != null);
        std.debug.assert(parent.?.layout.widths != null);
        std.debug.assert(parent.?.layout.mode_w.IsPreComputable());
        std.debug.assert(element.area.w < 0);
    }
    if (element.layout.mode_h == .Stretch) {
        std.debug.assert(parent != null);
        std.debug.assert(parent.?.layout.heights != null);
        std.debug.assert(parent.?.layout.mode_h.IsPreComputable());
        std.debug.assert(element.area.h < 0);
    }

    switch (element.mode) {
        .Block, .Button => {},
        .Rect => |rect| {
            // TODO: stretch-like rect dimensions
            element.area.w = rect.w;
            element.area.h = rect.h;
        },
        .Image => |image| {
            const image_size = &self.images.items[image.image].Size();
            element.area.w = image_size.w;
            element.area.h = image_size.h;
        },
        .Label => |label| {
            // TODO: account for text wrapping
            const label_size = &self.fonts.items[label.font].StringSize(label.str);
            element.area.w = label_size.w;
            element.area.h = label_size.h;
        },
    }
}

/// returns pointer to current element. pointer is only guaranteed to be valid
/// until the next call to DoContainer
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

pub fn DoRect(self: *GU, size: GUSize, color: u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Rect = size };
    element.layout.color = color;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
}

pub fn DoImage(self: *GU, image: GUImageHandle, color: ?u32) void {
    if (!self.DoElement(null)) return;
    defer self.EndElement();
    const element = self.GetElement();
    element.mode = .{ .Image = .{ .image = image } };
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
    element.mode = .{ .Label = .{ .font = font orelse 0, .str = str } };
    element.layout.color = color orelse 0xFFFFFFFF;
    element.layout.mode_w = .Fixed;
    element.layout.mode_h = .Fixed;
}

/// turns element into a button and executes the button logic. button is identified
/// internally by hash of the element id concatenated with str
/// to emulate DoButton behaviour, use mode .Press and return .activated or false if null
pub fn DoButtonLogic(self: *GU, mode: GUButtonMode, str: []const u8) ?GUButtonData {
    const element = self.GetElement();
    element.mode = .{ .Button = {} };

    const btn: *GUButton = get_button: {
        const btn_key = std.fmt.allocPrint(self.allocator, "{X:0>16}{s}", .{ element.id, str }) catch
            return null;
        const btn_info = self.buttons.getOrPut(btn_key) catch
            return null;

        const btn = btn_info.value_ptr;
        if (!btn_info.found_existing) {
            btn.* = GUButton{
                .state = .Idle,
                .mode = mode,
                .area = GURect.Zero,
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

    return GUButtonData{ .button = btn, .activated = activated };
}

// NOTE: id hash uses input fmt, not resolved formatted string
/// returns whether button was 'activated' (pressed)
pub fn DoButton(self: *GU, font: ?GUFontHandle, comptime fmt: []const u8, args: anytype) bool {
    if (!self.DoElement(null)) return false;
    defer self.EndElement();
    const element = self.GetElement();

    const btn = self.DoButtonLogic(.Press, fmt) orelse return false;

    element.layout.color = switch (btn.button.state) {
        .Idle => GUButton.COLOR_IDLE,
        .Hover => GUButton.COLOR_HOVER,
        .Down => GUButton.COLOR_DOWN,
    };
    element.layout.padding = .{ .w = GUButton.PADDING_HORIZONTAL, .h = GUButton.PADDING_VERTICAL };

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

    const btn = self.DoButtonLogic(.Press, fmt) orelse return false;
    if (btn.activated) active.* = !active.*;

    element.layout.color = switch (btn.button.state) {
        .Idle => if (active.*) GUButton.COLOR_DOWN else GUButton.COLOR_IDLE,
        .Hover => if (active.*) GUButton.COLOR_IDLE else GUButton.COLOR_HOVER,
        .Down => GUButton.COLOR_DOWN,
    };
    element.layout.padding = .{ .w = GUButton.PADDING_HORIZONTAL, .h = GUButton.PADDING_VERTICAL };

    self.DoLabel(font, null, fmt, args);

    return btn.activated;
}

pub fn DoLineBreak(self: *GU) void {
    self.element_queue_line_break = true;
}
