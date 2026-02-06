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
const GUBackend = GU.Backend;
const GUCornerShape = GU.CornerShape;
const GUTextureAtlas = GU.TextureAtlas;
const GUFontAtlas = GU.FontAtlas;
const GUTextureHandle = GU.TextureHandle;
const GUFontHandle = GU.FontHandle;
const GULayout = GU.Layout;
const GUButtonStyle = GU.ButtonStyle;
const GUCustomActionHandle = GU.CustomActionHandle;
const GURCCustom = GU.RCCustom;
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

const CNR_PX_LODS = [_][4][]const u32{
    generate_corner_pixels_lod(2, 4, sdf.sd_circle),
    generate_corner_pixels_lod(2, 4, sdf.sd_octagon),
    generate_corner_pixels_lod(2, 4, sdf.sd_chamfer_box),
    generate_corner_pixels_lod(2, 4, sdf.sd_superellipse),
    generate_corner_pixels_lod(2, 4, sdf.sd_quadratic_circle),
    generate_corner_pixels_lod(2, 4, sdf.sd_rhombus),
};

const RenderData = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    stored_clip: ?c.SDL_Rect,
    tex_corners: [CNR_SHAPES - 1][LOD_LEVELS]CornerTexture, // 4, 8, 16 and 32px radii
    const LOD_LEVELS = 4;
    const CNR_SHAPES = 7;
    pub const CNR_RECT: GUCornerShape = 0;
    pub const CNR_ROUND: GUCornerShape = 1;
    pub const CNR_ANGULAR: GUCornerShape = 2;
    pub const CNR_BEVELED: GUCornerShape = 3;
    pub const CNR_SUPERELLIPSE: GUCornerShape = 4;
    pub const CNR_QCIRCLE: GUCornerShape = 5;
    pub const CNR_RHOMBUS: GUCornerShape = 6;
    pub const ACT_DEMO_SINE: GUCustomActionHandle = 0;
    pub const ACT_DEMO_GRADIENT: GUCustomActionHandle = 1;

    pub const empty: RenderData = .{
        .window = null,
        .renderer = null,
        .stored_clip = null,
        .tex_corners = undefined,
    };

    pub fn Init() !RenderData {
        var rd: RenderData = .empty;

        SDLE(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
        try SDLE(c.SDL_CreateWindowAndRenderer("GU", WINDOW_W, WINDOW_H, 0, &rd.window, &rd.renderer));

        comptime assert(CNR_PX_LODS.len == CNR_SHAPES - 1);
        for (0..CNR_SHAPES - 1) |ci| {
            comptime assert(CNR_PX_LODS[ci].len == LOD_LEVELS);
            for (0..LOD_LEVELS) |li| {
                const width = pow(i32, 2, @as(i32, @intCast(li)) + 2) * 2;
                rd.tex_corners[ci][li] = try CornerTexture.Init(rd.renderer, width, CNR_PX_LODS[ci][li]);
            }
        }

        errdefer comptime unreachable;
        SDLEP(c.SDL_SetRenderDrawBlendMode(rd.renderer, c.SDL_BLENDMODE_BLEND));
        SDLE(c.SDL_SetWindowResizable(rd.window, true)) catch {};

        return rd;
    }

    pub fn Deinit(self: *RenderData) void {
        for (0..CNR_SHAPES - 1) |ci| for (0..LOD_LEVELS) |li| self.tex_corners[ci][li].Deinit();
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

    // TODO: respect corner shape/radius def in cmd
    fn EmitCustomCommand(ptr: *anyopaque, cmd: *const GURCCustom) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        switch (cmd.action) {
            ACT_DEMO_SINE => {
                var t: i64 = 0;
                SDLEP(c.SDL_GetCurrentTime(&t));
                const t_f = @as(f32, @floatFromInt(@mod(@divTrunc(t, c.SDL_NS_PER_MS), 2500)));
                const t_start = t_f * std.math.tau / 2500;
                const amp: f32 = cmd.rect.h / 2 - 1;
                const freq: f32 = amp * 2;
                var pts: [128]c.SDL_FPoint = undefined;
                for (&pts, 0..) |*p, i| {
                    const i_f = @as(f32, @floatFromInt(i));
                    const progress = i_f / pts.len;
                    const w = progress * cmd.rect.w;
                    p.x = cmd.rect.x + w;
                    p.y = cmd.rect.y + cmd.rect.h / 2 + @sin(t_start + w / freq) * amp;
                }
                const c1 = Color.fromInt(cmd.color);
                SDLEP(c.SDL_SetRenderDrawColor(self.renderer, c1.r, c1.g, c1.b, c1.a));
                SDLEP(c.SDL_RenderLines(self.renderer, &pts, pts.len));
            },
            ACT_DEMO_GRADIENT => {
                var pixels: [*]u32 = undefined;
                var pitch: c_int = undefined; // in bytes, not values
                if (c.SDL_LockTexture(app_global.gradient_texture, null, @ptrCast(&pixels), &pitch)) {
                    defer c.SDL_UnlockTexture(app_global.gradient_texture);
                    var t: i64 = 0;
                    SDLEP(c.SDL_GetCurrentTime(&t));
                    const xo: usize = 0xFF - @as(usize, @intCast(@mod(t >> 24, 0x3F)));
                    const yo: usize = 0xFF - @as(usize, @intCast(@mod(t >> 25, 0x3F)));
                    for (0..64) |y| {
                        for (0..64) |x| {
                            const xc: u32 = @truncate(((xo + x) % 0x3F) * 0xFF / 0x3F);
                            const yc: u32 = @truncate(((yo + y) % 0x3F) * 0xFF / 0x3F);
                            pixels[x + y * 64] = 0xFFFFFFFF ^ (xc << 8) ^ (yc << 16);
                        }
                    }
                    const c1 = Color.fromInt(cmd.color);
                    SDLEP(c.SDL_SetRenderDrawColor(self.renderer, c1.r, c1.g, c1.b, c1.a));
                    SDLEP(c.SDL_RenderTextureTiled(
                        self.renderer,
                        app_global.gradient_texture,
                        null,
                        1.0,
                        &.{ .x = cmd.rect.x, .y = cmd.rect.y, .w = cmd.rect.w, .h = cmd.rect.h },
                    ));
                }
            },
            else => unreachable,
        }
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

        assert(CNR_RECT == 0);
        if (cmd.corner_shape == CNR_RECT or cmd.corner_radius <= 0 or cmd.rect.w <= 1 or cmd.rect.h <= 1) {
            SDLEP(c.SDL_RenderFillRect(
                self.renderer,
                &.{ .x = cmd.rect.x, .y = cmd.rect.y, .w = cmd.rect.w, .h = cmd.rect.h },
            ));
            return;
        }

        assert(cmd.corner_shape > 0);
        assert(cmd.corner_shape < CNR_SHAPES);
        const dst_size: f32 = @min(@floor(@min(cmd.rect.w, cmd.rect.h) / 2), cmd.corner_radius);

        const tex_lod_index: usize =
            clamp(log2_int_ceil(usize, @intFromFloat(dst_size)), 2, 2 + LOD_LEVELS - 1) - 2;
        const tex: *CornerTexture = &self.tex_corners[cmd.corner_shape - 1][tex_lod_index];
        SDLEP(c.SDL_SetTextureAlphaMod(tex.texture, c1.a));
        SDLEP(c.SDL_SetTextureColorMod(tex.texture, c1.r, c1.g, c1.b));

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
            .fnEmitCustomCommand = EmitCustomCommand,
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
    fn_sdf: *const fn (p: Vec2, r: f32) f32,
) [N][]const u32 {
    var lod: [N][]const u32 = undefined;
    for (0..N) |i| lod[i] = &generate_corner_pixels(pow(usize, 2, i + S), fn_sdf);
    return lod;
}

fn generate_corner_pixels(
    comptime RADIUS: u32,
    fn_sdf: *const fn (p: Vec2, r: f32) f32,
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

const BASE_LAYOUT = GULayout{
    .mode_w = .Auto,
    .mode_h = .Auto,
    .color = 0x00000000,
    .widths = &[_]f32{ 200, -400, 200 },
    .heights = &[_]f32{ 100, -100 },
    .padding = Vec2{ .x = 9, .y = 9 },
    .gaps = Vec2{ .x = 6, .y = 6 },
    .auto_line_break = false,
    .corner_radius = 0,
    .corner_shape = RenderData.CNR_RECT,
};

const LAYOUT_RED = std.mem.zeroInit(GULayout, .{
    .color = 0x80000060,
});

const LAYOUT_WHITE = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .padding = Vec2{ .x = 4, .y = 4 },
    .corner_radius = 8,
    .corner_shape = RenderData.CNR_ROUND,
});

const LAYOUT_WHITE_BREAK = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .auto_line_break = true,
    .padding = Vec2{ .x = 4, .y = 4 },
    .corner_radius = 18,
    .corner_shape = RenderData.CNR_SUPERELLIPSE,
});

const LAYOUT_SHAPED_BOXES = [_]GULayout{
    generate_layout_shaped_box(RenderData.CNR_ROUND),
    generate_layout_shaped_box(RenderData.CNR_QCIRCLE),
    generate_layout_shaped_box(RenderData.CNR_SUPERELLIPSE),
    generate_layout_shaped_box(RenderData.CNR_RHOMBUS),
    generate_layout_shaped_box(RenderData.CNR_BEVELED),
    generate_layout_shaped_box(RenderData.CNR_ANGULAR),
};

fn generate_layout_shaped_box(shape: GUCornerShape) GULayout {
    return std.mem.zeroInit(GULayout, .{
        .color = 0x4040C0FF,
        .mode_w = .Fixed,
        .mode_h = .Fixed,
        .corner_radius = 32,
        .corner_shape = shape,
    });
}

const BASE_BUTTON_STYLE = GUButtonStyle{
    .PaddingVer = 2,
    .PaddingHor = 8,
    .CornerRad = 6,
    .CornerShape = RenderData.CNR_ROUND,
    .ColorIdle = 0x008000FF,
    .ColorHover = 0x00C000FF,
    .ColorDown = 0x004000FF,
};

const BASE_FONT: GUFontHandle = std.math.maxInt(GUFontHandle);

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

    btn_toggle: bool,
    btn_counter: usize,
    btn_color_loop: usize,

    gradient_texture: *c.SDL_Texture,

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

    app_global.gu = GU.Init(alloc, app_global.rd.GetBackend(), BASE_LAYOUT, BASE_BUTTON_STYLE, BASE_FONT);

    app_global.font = AsciiFont.Init(app_global.rd.renderer, FONT) catch |e|
        std.debug.panic("initializing AsciiFont failed: {s}", .{@errorName(e)});
    app_global.font_handle = app_global.gu.AddFont(app_global.font.GetFontAtlas()) catch |e|
        std.debug.panic("AddFont failed: {s}", .{@errorName(e)});
    app_global.gu.base_font = app_global.font_handle;

    for (0..app_global.textures.len) |ti| {
        app_global.textures[ti] =
            ImageTexture.Init(app_global.rd.renderer, TEXTURES[ti]) catch |e|
                std.debug.panic("initializing AsciiFont failed: {s}", .{@errorName(e)});
        app_global.texture_handles[ti] =
            app_global.gu.AddTexture(app_global.textures[ti].GetTextureAtlas()) catch |e|
                std.debug.panic("AddTexture failed: {s}", .{@errorName(e)});
    }

    app_global.gradient_texture = SDLEP(c.SDL_CreateTexture(
        app_global.rd.renderer,
        c.SDL_PIXELFORMAT_RGBA8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        64,
        64,
    ));

    app_global.btn_toggle = false;
    app_global.btn_counter = 0;
    app_global.btn_color_loop = 0;
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
    //const font = app.font_handle;
    const img1 = app.texture_handles[0];
    const img2 = app.texture_handles[1];

    const color_loop = [_]u32{ 0xC00000FF, 0x00C000FF, 0x0000C0FF };

    // NOTE: frame advance helper for debugging
    //if (!app.step) return c.SDL_APP_CONTINUE;
    //app.step = false;

    SDLEP(c.SDL_SetRenderDrawColor(rd.renderer, 0x00, 0x00, 0x22, 0xFF));
    SDLEP(c.SDL_RenderClear(rd.renderer));

    try gu.BeginFrame();

    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        if (gu.DoElement(&LAYOUT_RED)) {
            defer gu.EndElement();
            gu.DoLabel(0x00C000FF, "testblock1", .{});
        }
        gu.DoLineBreak();
        if (gu.DoElement(&LAYOUT_RED)) {
            defer gu.EndElement();
            gu.SetNextButtonMode(.Release);
            if (gu.DoButton("ReleaseButton", .{})) {
                app.btn_color_loop = (app.btn_color_loop + 1) % color_loop.len;
            }
        }
        gu.DoLineBreak();
        if (gu.DoElement(&LAYOUT_RED)) {
            defer gu.EndElement();
            gu.DoImage(img1, color_loop[app.btn_color_loop], 0.1);
        }
    }
    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        gu.DoLabel(0xC000C0FF, "testblock2", .{});
        if (gu.DoToggleButton(&app.btn_toggle, "ToggleButton: {any}", .{app.btn_toggle})) {
            // maybe do stuff here
        }
        if (app.btn_toggle) {
            gu.DoLabel(null, "only visible if b2 is on", .{});
        }
        gu.DoImage(img2, 0xC000C0FF, 0.25);
        gu.DoImage(img1, null, 0.25);
    }
    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        gu.SetElementGaps(4, 4);
        gu.DoLineBreak();
        gu.PushButtonPadding(12, 3);
        defer gu.PopButtonPadding();
        gu.PushButtonCorner(32, RenderData.CNR_SUPERELLIPSE);
        defer gu.PopButtonCorner();
        gu.SetNextButtonColor(0x800000FF, 0xC00000FF, 0x400000FF);
        if (gu.DoButton("SUB", .{})) app.btn_counter -|= 1;
        if (gu.DoButton("ADD", .{})) app.btn_counter +|= 1;
        gu.DoLineBreak();
        gu.DoLabel(0xCCCCFFFF, "{d:0>3}", .{app.btn_counter});
    }
    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        gu.DoLabel(0x0000C0FF, "testing... !!@$(#!QOIEANSHT)", .{});
        for (&LAYOUT_SHAPED_BOXES) |*layout| {
            gu.DoLineBreak();
            if (gu.DoElement(layout)) {
                defer gu.EndElement();
                const element = gu.GetElement();
                element.features.bShowRect = true;
                element.area.w = 64;
                element.area.h = 64;
            }
        }
    }
    if (gu.DoElement(&LAYOUT_WHITE_BREAK)) {
        defer gu.EndElement();
        gu.DoLabel(0x00C0C0FF, "testing... with auto linebreak!!", .{});
        if (gu.DoToggleButton(&app.btn_toggle, "ToggleButton", .{})) {
            // maybe do stuff here
        }
        if (app.btn_toggle) {
            gu.DoLabel(null, "only visible if b2 is on", .{});
        }
        gu.DoLineBreak();
        gu.DoImage(img1, null, 0.5);
        gu.DoImage(img2, null, 0.5);
    }
    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        var current_time: i64 = 0;
        SDLEP(c.SDL_GetCurrentTime(&current_time));
        const current_time_f = @as(f32, @floatFromInt(@mod(@divTrunc(current_time, c.SDL_NS_PER_MS), 2500)));
        gu.DoLabel(0xCCCCFFFF, "{d:0>5.3} {d:0>5.3}", .{ current_time_f / 1000, current_time_f / 2500 });
        gu.DoLineBreak();
        gu.DoCustomSurface(RenderData.ACT_DEMO_SINE, 192, 48);
        gu.DoLineBreak();
        gu.DoCustomSurface(RenderData.ACT_DEMO_GRADIENT, 192, 48);
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
