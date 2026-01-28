const std = @import("std");

const assert = std.debug.assert;
const clamp = std.math.clamp;
const log2_int_ceil = std.math.log2_int_ceil;
const pow = std.math.pow;
const sign = std.math.sign;

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLEP = @import("c.zig").SDLEP;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const GU = @import("gu.zig");
const GUBackend = GU.GUBackend;
const GUCorner = GU.GUCorner;
const GUTextureAtlas = GU.GUTextureAtlas;
const GUFontAtlas = GU.GUFontAtlas;
const GUTextureHandle = GU.TextureHandle;
const GUFontHandle = GU.FontHandle;
const GULayout = GU.GULayout;
const GURCRect = GU.RCRect;
const GURCText = GU.RCText;
const GURCClip = GU.RCClip;

const Vec2 = @import("m_vec2.zig");
const Rect = @import("m_rect.zig");
const Color = @import("m_color.zig").Color;
const sdf = @import("m_sdf.zig");

const WINDOW_W = 800;
const WINDOW_H = 600;

const FONT = @embedFile("ascii-font");
const TEXTURES: [2][]const u8 = .{ @embedFile("yuriko1"), @embedFile("yuriko2") };

// FIXME: assumes tile size/coordinates for now (implemented as a pure port of test code as stopgap)
const AsciiFont = struct {
    texture: *c.SDL_Texture,
    renderer: ?*c.SDL_Renderer,

    // NOTE: BMP can be transparent; convert from PNG using online converter if
    // your photo app can't export BMP
    pub fn Init(renderer: ?*c.SDL_Renderer, bmp: []const u8) !AsciiFont {
        const stream: *c.SDL_IOStream = try SDLE(c.SDL_IOFromConstMem(bmp.ptr, bmp.len));
        const surface: *c.SDL_Surface = try SDLE(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);
        const texture: *c.SDL_Texture = try SDLE(c.SDL_CreateTextureFromSurface(renderer, surface));
        errdefer comptime unreachable;
        return AsciiFont{ .texture = texture, .renderer = renderer };
    }

    pub fn Deinit(self: *AsciiFont) void {
        c.SDL_DestroyTexture(self.texture);
    }

    // TODO: use alpha from input color
    fn SetColor(ptr: *anyopaque, color: u32) void {
        const self: *AsciiFont = @ptrCast(@alignCast(ptr));
        const rgba = Color.fromInt(color);
        SDLEP(c.SDL_SetTextureColorMod(self.texture, rgba.r, rgba.g, rgba.b));
    }

    // FONT RELATED

    // TODO: use CharSize
    fn StringSize(_: *anyopaque, str: []const u8) Vec2 {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        assert(std.mem.min(u8, str) >= ' ');
        assert(std.mem.max(u8, str) < 127);
        return .{ .x = 10 * @as(f32, @floatFromInt(str.len)), .y = 21 };
    }

    // TODO: use data table/mapping for individual char data
    fn CharSize(_: *anyopaque, _: u8) Vec2 {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return Vec2{ .x = 10, .y = 21 };
    }

    fn DrawString(ptr: *anyopaque, str: []const u8, pos: *const Vec2) void {
        const self: *AsciiFont = @ptrCast(@alignCast(ptr));
        assert(std.mem.min(u8, str) >= ' ');
        assert(std.mem.max(u8, str) < 127);
        var rolling_pos = pos.*;
        for (str) |char| {
            DrawChar(ptr, char, &rolling_pos);
            rolling_pos.x += CharSize(self, char).x;
        }
    }

    fn DrawChar(ptr: *anyopaque, char: u8, pos: *const Vec2) void {
        const self: *AsciiFont = @ptrCast(@alignCast(ptr));
        assert(char >= ' ');
        assert(char < 127);
        const size = CharSize(ptr, char);
        const n = char - ' ';
        const i: f32 = @as(f32, @floatFromInt(n % 16)) * size.x;
        const j: f32 = @as(f32, @floatFromInt(n / 16)) * size.y;
        SDLEP(c.SDL_RenderTexture(
            self.renderer,
            self.texture,
            &.{ .x = i, .y = j, .w = size.x, .h = size.y },
            &.{ .x = pos.x, .y = pos.y, .w = size.x, .h = size.y },
        ));
    }

    pub fn GetFontAtlas(self: *AsciiFont) GUFontAtlas {
        return GUFontAtlas{
            .ptr = self,
            .fnDrawString = DrawString,
            .fnDrawChar = DrawChar,
            .fnStringSize = StringSize,
            .fnCharSize = CharSize,
            .fnSetColor = SetColor,
        };
    }
};

const ImageTexture = struct {
    texture: *c.SDL_Texture,
    renderer: ?*c.SDL_Renderer,

    // NOTE: BMP can be transparent; convert from PNG using online converter if
    // your photo app can't export BMP
    pub fn Init(renderer: ?*c.SDL_Renderer, bmp: []const u8) !ImageTexture {
        const stream: *c.SDL_IOStream = try SDLE(c.SDL_IOFromConstMem(bmp.ptr, bmp.len));
        const surface: *c.SDL_Surface = try SDLE(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);
        const texture: *c.SDL_Texture = try SDLE(c.SDL_CreateTextureFromSurface(renderer, surface));
        errdefer comptime unreachable;
        return ImageTexture{ .texture = texture, .renderer = renderer };
    }

    pub fn Deinit(self: *ImageTexture) void {
        c.SDL_DestroyTexture(self.texture);
    }

    // TODO: use alpha from input color
    fn SetColor(ptr: *anyopaque, color: u32) void {
        const self: *ImageTexture = @ptrCast(@alignCast(ptr));
        const rgba = Color.fromInt(color);
        SDLEP(c.SDL_SetTextureColorMod(self.texture, rgba.r, rgba.g, rgba.b));
    }

    fn Draw(ptr: *anyopaque, pos: *const Vec2) void {
        const self: *ImageTexture = @ptrCast(@alignCast(ptr));
        const size = Size(ptr);
        SDLEP(c.SDL_RenderTexture(
            self.renderer,
            self.texture,
            null,
            &.{ .x = pos.x, .y = pos.y, .w = size.x, .h = size.y },
        ));
    }

    fn Size(ptr: *anyopaque) Vec2 {
        const self: *ImageTexture = @ptrCast(@alignCast(ptr));
        return Vec2{ .x = @floatFromInt(self.texture.w), .y = @floatFromInt(self.texture.h) };
    }

    pub fn GetTextureAtlas(self: *ImageTexture) GUTextureAtlas {
        return GUTextureAtlas{
            .ptr = self,
            .fnDraw = Draw,
            .fnSize = Size,
            .fnSetColor = SetColor,
        };
    }
};

//------------------------------------------------------------------------------

const CornerTexture = struct {
    texture: *c.SDL_Texture,
    size: f32,

    pub fn Init(
        renderer: ?*c.SDL_Renderer,
        width: i32,
        px_data: []const u32, // RGBA8888
    ) !CornerTexture {
        assert(std.math.isPowerOfTwo(width));
        assert(px_data.len == width * width);

        const px_fmt = c.SDL_PIXELFORMAT_RGBA8888;
        const sfc: *c.SDL_Surface =
            SDLEP(c.SDL_CreateSurfaceFrom(width, width, px_fmt, @constCast(px_data.ptr), width * 4));
        defer c.SDL_DestroySurface(sfc);
        const tex: *c.SDL_Texture = SDLEP(c.SDL_CreateTextureFromSurface(renderer, sfc));

        return CornerTexture{ .texture = tex, .size = @floatFromInt(@divExact(width, 2)) };
    }

    pub fn InitBMP(renderer: ?*c.SDL_Renderer, bmp: []const u8) !CornerTexture {
        const stream: *c.SDL_IOStream = try SDLE(c.SDL_IOFromConstMem(bmp.ptr, bmp.len));
        const surface: *c.SDL_Surface = try SDLE(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);
        const t: *c.SDL_Texture = try SDLE(c.SDL_CreateTextureFromSurface(renderer, surface));

        assert(t.w == t.h);
        assert(@mod(t.w, 2) == 0);
        return CornerTexture{ .texture = t, .size = @floatFromInt(@divExact(t.w, 2)) };
    }

    pub fn Deinit(self: *CornerTexture) void {
        c.SDL_DestroyTexture(self.texture);
    }
};

//------------------------------------------------------------------------------

const CNR_PX_LOD_CIRCLE = generate_corner_pixels_lod(2, 4, sdf.sd_circle);
const CNR_PX_LOD_CHAMFER = generate_corner_pixels_lod(2, 4, sdf.sd_chamfer_box);
const CNR_PX_LOD_OCTAGON = generate_corner_pixels_lod(2, 4, sdf.sd_octagon);
const CNR_PX_LOD_SUPERELLIPSE = generate_corner_pixels_lod(2, 4, sdf.sd_superellipse);

const RenderData = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    stored_clip: ?c.SDL_Rect,
    tex_corner_rnd_lod: [LOD_LEVELS]CornerTexture, // 4, 8, 16 and 32px radii
    tex_corner_ang_lod: [LOD_LEVELS]CornerTexture,
    tex_corner_bev_lod: [LOD_LEVELS]CornerTexture,
    tex_corner_sel_lod: [LOD_LEVELS]CornerTexture, // superellipse

    pub const empty: RenderData = .{
        .window = null,
        .renderer = null,
        .stored_clip = null,
        .tex_corner_rnd_lod = undefined,
        .tex_corner_ang_lod = undefined,
        .tex_corner_bev_lod = undefined,
        .tex_corner_sel_lod = undefined,
    };

    const LOD_LEVELS = 4;

    pub fn Init() !RenderData {
        var rd: RenderData = .empty;

        SDLE(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
        try SDLE(c.SDL_CreateWindowAndRenderer("GU", WINDOW_W, WINDOW_H, 0, &rd.window, &rd.renderer));

        comptime assert(CNR_PX_LOD_CIRCLE.len == LOD_LEVELS);
        comptime assert(CNR_PX_LOD_CHAMFER.len == LOD_LEVELS);
        comptime assert(CNR_PX_LOD_OCTAGON.len == LOD_LEVELS);
        comptime assert(CNR_PX_LOD_SUPERELLIPSE.len == LOD_LEVELS);
        for (0..LOD_LEVELS) |i| {
            const width = pow(i32, 2, @as(i32, @intCast(i)) + 2) * 2;
            rd.tex_corner_rnd_lod[i] = try CornerTexture.Init(rd.renderer, width, CNR_PX_LOD_CIRCLE[i]);
            rd.tex_corner_bev_lod[i] = try CornerTexture.Init(rd.renderer, width, CNR_PX_LOD_CHAMFER[i]);
            rd.tex_corner_ang_lod[i] = try CornerTexture.Init(rd.renderer, width, CNR_PX_LOD_OCTAGON[i]);
            rd.tex_corner_sel_lod[i] = try CornerTexture.Init(rd.renderer, width, CNR_PX_LOD_SUPERELLIPSE[i]);
        }

        errdefer comptime unreachable;
        SDLEP(c.SDL_SetRenderDrawBlendMode(rd.renderer, c.SDL_BLENDMODE_BLEND));
        SDLE(c.SDL_SetWindowResizable(rd.window, true)) catch {};

        return rd;
    }

    pub fn Deinit(self: *RenderData) void {
        for (0..LOD_LEVELS) |i| {
            self.tex_corner_rnd_lod[i].Deinit();
            self.tex_corner_bev_lod[i].Deinit();
            self.tex_corner_ang_lod[i].Deinit();
            self.tex_corner_sel_lod[i].Deinit();
        }
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
    }

    // BACKEND

    fn GetSurfaceDimensions(ptr: *anyopaque) Vec2 {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        var screen_w: c_int = undefined;
        var screen_h: c_int = undefined;
        SDLEP(c.SDL_GetRenderOutputSize(self.renderer, &screen_w, &screen_h));
        return Vec2{ .x = @floatFromInt(screen_w), .y = @floatFromInt(screen_h) };
    }

    fn GetClip(ptr: *anyopaque) Rect {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        if (self.stored_clip) |*clip| {
            return Rect{
                .x = @as(f32, @floatFromInt(clip.x)),
                .y = @as(f32, @floatFromInt(clip.y)),
                .w = @as(f32, @floatFromInt(clip.w)),
                .h = @as(f32, @floatFromInt(clip.h)),
            };
        }
        const sd = GetSurfaceDimensions(ptr);
        return Rect{ .x = 0, .y = 0, .w = sd.w, .h = sd.h };
    }

    fn DrawRect(ptr: *anyopaque, cmd: *const GURCRect) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        const c1 = Color.fromInt(cmd.color);
        SDLEP(c.SDL_SetRenderDrawColor(self.renderer, c1.r, c1.g, c1.b, c1.a));

        // FIXME: integrate this in with the rest, so that textured rects can
        //  take advantage of things like corner rounding
        if (cmd.texture) |img| {
            const atlas: *ImageTexture = @ptrCast(@alignCast(img.ptr));
            SDLEP(c.SDL_SetTextureColorMod(atlas.texture, c1.r, c1.g, c1.b));
            SDLEP(c.SDL_RenderTexture(
                atlas.renderer,
                atlas.texture,
                null,
                &.{ .x = cmd.rect.x, .y = cmd.rect.y, .w = cmd.rect.w, .h = cmd.rect.h },
            ));
            return;
        }

        if (cmd.corner.style == .None or cmd.corner.radius <= 0 or cmd.rect.w <= 1 or cmd.rect.h <= 1) {
            SDLEP(c.SDL_RenderFillRect(
                self.renderer,
                &.{ .x = cmd.rect.x, .y = cmd.rect.y, .w = cmd.rect.w, .h = cmd.rect.h },
            ));
            return;
        }

        const tex_lod_index: usize =
            clamp(log2_int_ceil(usize, @intFromFloat(cmd.corner.radius)), 2, 2 + LOD_LEVELS - 1) - 2;
        const tex: *CornerTexture = switch (cmd.corner.style) {
            .Round => &self.tex_corner_rnd_lod[tex_lod_index],
            .Custom1 => &self.tex_corner_ang_lod[tex_lod_index],
            .Custom2 => &self.tex_corner_bev_lod[tex_lod_index],
            .Custom3 => &self.tex_corner_sel_lod[tex_lod_index],
            else => unreachable,
        };
        SDLEP(c.SDL_SetTextureAlphaMod(tex.texture, c1.a));
        SDLEP(c.SDL_SetTextureColorMod(tex.texture, c1.r, c1.g, c1.b));

        const dst_size: f32 = @min(@floor(@min(cmd.rect.w, cmd.rect.h) / 2), cmd.corner.radius);
        SDLEP(c.SDL_RenderTexture9Grid(
            self.renderer,
            tex.texture,
            null,
            tex.size,
            tex.size,
            tex.size,
            tex.size,
            dst_size / tex.size,
            &.{ .x = cmd.rect.x, .y = cmd.rect.y, .w = cmd.rect.w, .h = cmd.rect.h },
        ));
    }

    fn DrawString(_: *anyopaque, cmd: *const GURCText) void {
        //const self: *RenderData = @alignCast(@ptrCast(ptr));
        cmd.font.SetColor(cmd.color);
        cmd.font.DrawString(cmd.str, &cmd.pos);
    }

    fn SetClip(ptr: *anyopaque, cmd: *const GURCClip) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        const rect = c.SDL_Rect{
            .x = @as(c_int, @intFromFloat(cmd.area.x)),
            .y = @as(c_int, @intFromFloat(cmd.area.y)),
            .w = @as(c_int, @intFromFloat(cmd.area.w)),
            .h = @as(c_int, @intFromFloat(cmd.area.h)),
        };
        SDLEP(c.SDL_SetRenderClipRect(self.renderer, &rect));
    }

    fn BeginRendering(ptr: *anyopaque) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        assert(self.stored_clip == null);
        if (c.SDL_RenderClipEnabled(self.renderer)) {
            var clip: c.SDL_Rect = undefined;
            SDLEP(c.SDL_GetRenderClipRect(self.renderer, &clip));
            self.stored_clip = clip;
        }
    }

    fn EndRendering(ptr: *anyopaque) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        SDLEP(c.SDL_SetRenderClipRect(
            self.renderer,
            if (self.stored_clip) |*clip| clip else null,
        ));
        self.stored_clip = null;
    }

    pub fn GetBackend(self: *RenderData) GUBackend {
        return GUBackend{
            .ptr = self,
            .fnGetSurfaceDimensions = GetSurfaceDimensions,
            .fnDrawRect = DrawRect,
            .fnDrawString = DrawString,
            .fnSetClip = SetClip,
            .fnBeginRendering = BeginRendering,
            .fnEndRendering = EndRendering,
        };
    }
};

fn generate_corner_pixels_lod(
    comptime S: usize,
    comptime N: usize,
    fn_sdf: *const fn (x: f32, y: f32, r: f32) f32,
) [N][]const u32 {
    var lod: [N][]const u32 = undefined;
    for (0..N) |i| lod[i] = &generate_corner_pixels(pow(usize, 2, i + S), fn_sdf);
    return lod;
}

fn generate_corner_pixels(
    comptime RADIUS: u32,
    fn_sdf: *const fn (x: f32, y: f32, r: f32) f32,
) [RADIUS * RADIUS * 4]u32 {
    assert(std.math.isPowerOfTwo(RADIUS));
    assert(@inComptime());

    var field: [RADIUS * RADIUS * 4]f32 = undefined;
    var pixels: [RADIUS * RADIUS * 4]u32 = undefined;
    sdf.render_whole_from_quadrant(RADIUS, &field, fn_sdf);
    for (field, &pixels) |f, *p| p.* = 0xFFFFFF00 | @as(u32, @intFromFloat(clamp(-f, 0, 1) * 255));
    return pixels;
}

//------------------------------------------------------------------------------

const StyleAngular = GUCorner.Style.Custom1;
const StyleBeveled = GUCorner.Style.Custom2;
const StyleSuperellipse = GUCorner.Style.Custom3;

const BASE_LAYOUT = GULayout{
    .mode_w = .Auto,
    .mode_h = .Auto,
    .color = 0x00000000,
    .widths = &[_]f32{ 200, -400, 200 },
    .heights = &[_]f32{ 100, -100 },
    .padding = Vec2{ .x = 9, .y = 9 },
    .gaps = Vec2{ .x = 6, .y = 6 },
    .auto_line_break = false,
    .corner = .{ .radius = 0, .style = .None },
};

const LAYOUT_RED = std.mem.zeroInit(GULayout, .{
    .color = 0x80000060,
});

const LAYOUT_WHITE = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .padding = Vec2{ .x = 4, .y = 4 },
    .corner = .{ .style = .Round, .radius = 8 },
});

const LAYOUT_WHITE_BREAK = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .auto_line_break = true,
    .padding = Vec2{ .x = 4, .y = 4 },
    .corner = .{ .style = StyleSuperellipse, .radius = 18 },
});

const LAYOUT_SUPERELLIPSE_BOX = std.mem.zeroInit(GULayout, .{
    .corner = .{ .style = StyleSuperellipse, .radius = 32 },
    .color = 0x4040C0FF,
    .mode_w = .Fixed,
    .mode_h = .Fixed,
});

//------------------------------------------------------------------------------

const App = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    alloc: std.mem.Allocator,

    rd: RenderData,
    gu: GU,

    font: AsciiFont,
    font_handle: GUFontHandle,

    textures: [2]ImageTexture,
    texture_handles: [2]GUTextureHandle,

    b2toggle: bool,
    step: bool,
};

var app_global: App = undefined;

pub export fn SDL_AppInit(app: **App, argc: c_int, argv: [*][:0]u8) c.SDL_AppResult {
    _ = argc;
    _ = argv;

    app_global.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    app_global.alloc = app_global.gpa.allocator();
    const alloc = app_global.alloc;

    c.SDL_SetMainReady();
    SDLEP(c.SDL_SetAppMetadata("GU", "0.0.0", "com.galeforce.gu"));
    SDLEP(c.SDL_Init(c.SDL_INIT_VIDEO));

    // SDL VIDEO INIT

    app_global.rd = RenderData.Init() catch |e|
        std.debug.panic("initializing RenderData failed: {s}", .{@errorName(e)});

    // UI-RELATED

    app_global.gu = GU.Init(alloc, app_global.rd.GetBackend(), BASE_LAYOUT);

    app_global.font = AsciiFont.Init(app_global.rd.renderer, FONT) catch |e|
        std.debug.panic("initializing AsciiFont failed: {s}", .{@errorName(e)});
    app_global.font_handle = app_global.gu.AddFont(app_global.font.GetFontAtlas()) catch |e|
        std.debug.panic("AddFont failed: {s}", .{@errorName(e)});
    for (0..app_global.textures.len) |ti| {
        app_global.textures[ti] =
            ImageTexture.Init(app_global.rd.renderer, TEXTURES[ti]) catch |e|
                std.debug.panic("initializing AsciiFont failed: {s}", .{@errorName(e)});
        app_global.texture_handles[ti] =
            app_global.gu.AddTexture(app_global.textures[ti].GetTextureAtlas()) catch |e|
                std.debug.panic("AddTexture failed: {s}", .{@errorName(e)});
    }

    app_global.b2toggle = false;
    app_global.step = true;

    app.* = &app_global;
    return c.SDL_APP_CONTINUE;
}

// normally WM_PAINT would be handled here to smoothly re-render during resize,
// but SDL3 has no mechanism for accessing it in a 'normal' app, so we use a
// callback app, which handles that case for us
pub export fn SDL_AppEvent(app: *App, event: *c.SDL_Event) c.SDL_AppResult {
    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            app.gu.mouse_pt.x = event.motion.x;
            app.gu.mouse_pt.y = event.motion.y;
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            if (event.button.button != c.SDL_BUTTON_LEFT) return c.SDL_APP_CONTINUE;
            const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
            app.gu.mouse_left.Accumulate(down);
        },
        c.SDL_EVENT_KEY_DOWN => {
            if (event.key.scancode == c.SDL_SCANCODE_RETURN)
                app.step = true;
        },
        else => {},
    }
    return c.SDL_APP_CONTINUE;
}

pub export fn SDL_AppIterate(app: *App) c.SDL_AppResult {
    const rd = &app.rd;
    const gu = &app.gu;
    const font = app.font_handle;
    const img1 = app.texture_handles[0];
    const img2 = app.texture_handles[1];

    // NOTE: frame advance helper for debugging
    //if (!app.step) return c.SDL_APP_CONTINUE;
    //app.step = false;

    SDLEP(c.SDL_SetRenderDrawColor(rd.renderer, 0x00, 0x00, 0x22, 0xFF));
    SDLEP(c.SDL_RenderClear(rd.renderer));

    try gu.BeginFrame();

    if (gu.DoContainer(&LAYOUT_WHITE)) {
        defer gu.EndContainer();
        if (gu.DoContainer(&LAYOUT_RED)) {
            defer gu.EndContainer();
            gu.DoLabel(null, 0x00C000FF, "testblock1", .{});
        }
        gu.DoLineBreak();
        if (gu.DoContainer(&LAYOUT_RED)) {
            defer gu.EndContainer();
            if (gu.DoButton(font, "Button", .{})) {
                std.log.debug("b1 activation result!!", .{});
            }
        }
        gu.DoLineBreak();
        if (gu.DoContainer(&LAYOUT_RED)) {
            defer gu.EndContainer();
            gu.DoImage(img1, 0x00C000FF, 0.1);
        }
    }
    if (gu.DoContainer(&LAYOUT_WHITE)) {
        defer gu.EndContainer();
        gu.DoLabel(null, 0xC000C0FF, "testblock2", .{});
        if (gu.DoToggleButton(&app.b2toggle, font, "ToggleButton: {any}", .{app.b2toggle})) {
            std.log.debug("b2 toggled!!", .{});
        }
        if (app.b2toggle) {
            gu.DoLabel(null, null, "only visible if b2 is on", .{});
        }
        gu.DoImage(img2, 0xC000C0FF, 0.25);
        gu.DoImage(img1, null, 0.25);
    }
    if (gu.DoContainer(&LAYOUT_WHITE)) {
        defer gu.EndContainer();
        gu.DoRect(.{ .x = 64, .y = 64 }, 0x000055FF);
        gu.DoLineBreak();
        gu.DoLabel(font, 0xC00000FF, "testblock3", .{});
        gu.DoLineBreak();
        gu.DoRect(.{ .x = 64, .y = 64 }, 0x2222AAFF); // old outline color
    }
    if (gu.DoContainer(&LAYOUT_WHITE)) {
        defer gu.EndContainer();
        gu.DoLabel(null, 0x0000C0FF, "testing... !!@$(#!QOIEANSHT)", .{});
        gu.DoLineBreak();
        if (gu.DoContainer(&LAYOUT_SUPERELLIPSE_BOX)) {
            defer gu.EndContainer();
            const element = gu.GetContainer();
            element.features.bShowRect = true;
            element.area.w = 64;
            element.area.h = 64;
        }
    }
    if (gu.DoContainer(&LAYOUT_WHITE_BREAK)) {
        defer gu.EndContainer();
        gu.DoLabel(null, 0x00C0C0FF, "testing... with auto linebreak!!", .{});
        if (gu.DoToggleButton(&app.b2toggle, font, "ToggleButton", .{})) {
            std.log.debug("b2 toggled!!", .{});
        }
        if (app.b2toggle) {
            gu.DoLabel(null, null, "only visible if b2 is on", .{});
        }
        gu.DoLineBreak();
        gu.DoImage(img1, null, 0.5);
        gu.DoImage(img2, null, 0.5);
    }
    if (gu.DoContainer(&LAYOUT_WHITE)) {
        defer gu.EndContainer();
        gu.DoLabel(null, 0xC0C000FF, "testing... !!@$(#!QOIEANSHT)", .{});
    }

    gu.EndFrame();

    SDLEP(c.SDL_RenderPresent(rd.renderer));

    return c.SDL_APP_CONTINUE;
}

pub export fn SDL_AppQuit(app: *App, _: c.SDL_AppResult) void {
    app.font.Deinit();
    app.gu.Deinit();
    app.rd.Deinit();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    _ = c.SDL_main(@intCast(args.len), @ptrCast(args.ptr));
}
