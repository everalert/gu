const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const bytesAsSlice = std.mem.bytesAsSlice;
const clamp = std.math.clamp;
const log2_int_ceil = std.math.log2_int_ceil;
const pow = std.math.pow;
const sign = std.math.sign;
const maxInt = std.math.maxInt;

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLEP = @import("c.zig").SDLEP;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const GU = @import("gu.zig");
const GUBackend = GU.Backend;
const GUCornerShape = GU.CornerShape;
const GUTextureAtlas = GU.TextureAtlas;
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

const TEXTURES: [2][]const u8 = .{ @embedFile("yuriko1"), @embedFile("yuriko2") };

const FONT_STYLES = [1]struct { usize, f32 }{.{ 0, 21 }};
const FONTS = [1]struct { []const u8, u32, f32, Vec2, []const Vec2 }{
    .{ @embedFile("ascii-font-lod"), 16, 7, .init(128, 96), &.{
        .init(512, 192), .init(512, 0), .init(0, 0),
    } },
};

// FIXME: do proper ZII approach and see how it pans out
// TODO: tracking of number of attempted assignments, to help tune buffer sizes
// TODO: ?? externally managed textures? (decouple texture lifetime)
// NOTE: to keep things simple for now, no delete functions; must free entire thing
fn FontRenderer(
    comptime NumFnt: usize,
    comptime NumSty: usize,
    comptime NumTex: usize,
    comptime NumGly: usize,
    comptime NumLOD: usize,
) type {
    const SIZE_FNT = NumFnt * @sizeOf(Font);
    const SIZE_STY = NumSty * @sizeOf(FontStyle);
    const SIZE_LOD = NumLOD * @sizeOf(FontLOD);
    const SIZE_GLY = NumGly * @sizeOf(Glyph);
    const SIZE_TEX = NumTex * @sizeOf(*c.SDL_Texture);
    const OFFSET_FNT = 0;
    const OFFSET_STY = OFFSET_FNT + SIZE_FNT;
    const OFFSET_LOD = OFFSET_STY + SIZE_STY;
    const OFFSET_GLY = OFFSET_LOD + SIZE_LOD;
    const OFFSET_TEX = OFFSET_GLY + SIZE_GLY;
    const REQUIRED_BYTES = SIZE_FNT + SIZE_STY + SIZE_LOD + SIZE_GLY + SIZE_TEX;

    return struct {
        Renderer: ?*c.SDL_Renderer,
        BackingMemory: []u8,
        BufFnt: []Font,
        BufSty: []FontStyle,
        BufLOD: []FontLOD,
        BufGly: []Glyph,
        BufTex: []*c.SDL_Texture,
        BufFntCount: usize,
        BufStyCount: usize,
        BufLODCount: usize,
        BufGlyCount: usize,
        BufTexCount: usize,

        const FontRendererT = @This();

        pub fn Init(alloc: Allocator, renderer: ?*c.SDL_Renderer) Allocator.Error!FontRendererT {
            const buf = try alloc.alloc(u8, REQUIRED_BYTES);
            return FontRendererT{
                .Renderer = renderer,
                .BackingMemory = buf,
                .BufFnt = @alignCast(bytesAsSlice(Font, buf[OFFSET_FNT .. OFFSET_FNT + SIZE_FNT])),
                .BufSty = @alignCast(bytesAsSlice(FontStyle, buf[OFFSET_STY .. OFFSET_STY + SIZE_STY])),
                .BufLOD = @alignCast(bytesAsSlice(FontLOD, buf[OFFSET_LOD .. OFFSET_LOD + SIZE_LOD])),
                .BufGly = @alignCast(bytesAsSlice(Glyph, buf[OFFSET_GLY .. OFFSET_GLY + SIZE_GLY])),
                .BufTex = @alignCast(bytesAsSlice(*c.SDL_Texture, buf[OFFSET_TEX .. OFFSET_TEX + SIZE_TEX])),
                .BufFntCount = 0,
                .BufStyCount = 0,
                .BufLODCount = 0,
                .BufGlyCount = 0,
                .BufTexCount = 0,
            };
        }

        /// must use same allocator as used to init
        pub fn Deinit(self: *FontRendererT, alloc: Allocator) void {
            for (0..self.BufTexCount) |ti| c.SDL_DestroyTexture(self.BufTex[ti]);
            alloc.free(self.BackingMemory);
        }

        //-----------------------------
        // setup code

        // NOTE: see `FontAddAsciiMono` for typical setup flow

        // NOTE: BMP can be transparent; convert from PNG using online converter
        // if your photo app can't export BMP
        /// returns handle to texture, or a null/safe handle on failure
        pub fn TextureAdd(self: *FontRendererT, bmp: []const u8) usize {
            const next_i = self.BufTexCount;
            if (next_i >= NumTex) return maxInt(usize); // null handle

            const stream = SDLE(c.SDL_IOFromConstMem(bmp.ptr, bmp.len)) catch return maxInt(usize);
            const surface = SDLE(c.SDL_LoadBMP_IO(stream, true)) catch return maxInt(usize);
            defer c.SDL_DestroySurface(surface);
            const texture = SDLE(c.SDL_CreateTextureFromSurface(self.Renderer, surface)) catch
                return maxInt(usize);
            //errdefer comptime unreachable;

            self.BufTex[next_i] = texture;
            self.BufTexCount += 1;
            return next_i;
        }

        /// returns handle to font lod, or a null/safe handle on failure
        /// @pixels     texture handle
        /// @size       pixel height of glyphs in this LOD
        pub fn FontLODAdd(
            self: *FontRendererT,
            pixels: usize,
            glyph_start: usize,
            glyph_count: usize,
            size: usize,
        ) usize {
            assert(std.math.isPowerOfTwo(size));
            const next_i = self.BufLODCount;

            if (@intFromBool(next_i < NumLOD) &
                @intFromBool(glyph_start + glyph_count <= self.BufGlyCount) == 0)
                return maxInt(usize); // null handle;

            self.BufLOD[next_i] = FontLOD{
                .Pixels = pixels,
                .GlyphStart = glyph_start,
                .GlyphCount = glyph_count,
                .Size = size,
            };

            self.BufLODCount += 1;
            return next_i;
        }

        /// returns handle to glyph, or a null/safe handle on failure
        pub fn GlyphAdd(self: *FontRendererT, advance_x: f32, region: Rect) usize {
            const next_i = self.BufGlyCount;

            if (@intFromBool(next_i < NumGly) == 0)
                return maxInt(usize); // null handle;

            self.BufGly[next_i] = Glyph{
                .AdvanceX = advance_x,
                .PixelRegion = region,
            };

            self.BufGlyCount += 1;
            return next_i;
        }

        /// returns handle to font config, or a null/safe handle on failure
        pub fn StyleAdd(self: *FontRendererT, font: usize, size: f32) usize {
            assert(size > 0);
            const next_i = self.BufStyCount;

            if (@intFromBool(next_i < NumSty) &
                @intFromBool(font < self.BufFntCount) == 0)
                return maxInt(usize); // null handle;

            self.BufSty[next_i] = FontStyle{ .Font = font, .Size = size };

            self.BufStyCount += 1;
            return next_i;
        }

        /// returns handle to font, or a null/safe handle on failure
        pub fn FontAdd(
            self: *FontRendererT,
            codepoint_min: u21,
            codepoint_max: u21,
            lod_start: usize,
            lod_count: usize,
        ) usize {
            assert(codepoint_max > codepoint_min);
            assert(lod_count > 0);
            const next_i = self.BufFntCount;

            if (@intFromBool(next_i < NumFnt) &
                @intFromBool(lod_start + lod_count <= self.BufLODCount) == 0)
                return maxInt(usize); // null handle;

            assert(self.BufLOD[lod_start].GlyphCount == codepoint_max - codepoint_min + 1);
            for (lod_start + 1..lod_start + lod_count) |li| {
                assert(self.BufLOD[li].GlyphCount == codepoint_max - codepoint_min + 1);
                assert(self.BufLOD[li].Size == self.BufLOD[li - 1].Size * 2); // sequential powers of 2
            }

            self.BufFnt[next_i] = Font{
                .CodepointMin = codepoint_min,
                .CodepointMax = codepoint_max,
                .LODStart = lod_start,
                .LODCount = lod_count,
            };

            self.BufFntCount += 1;
            return next_i;
        }

        /// creates a monospace ascii font from a standard input structure, and
        /// returns the associated font handle. each LOD is assumed to be a 16*6
        /// grid of characters from 0x20 through 0x7F (96 chars).
        /// @bmp            bmp-formatted bytes containing pixels for all LODs
        /// @base_size      line height of the lowest LOD, doubled for every
        ///                 successive LOD, which must be a power of 2
        /// @base_advance   advance of the lowest LOD, doubled for every
        ///                 successive LOD
        /// @base_area      texture area of the lowest LOD, doubled for every
        ///                 successive LOD. area must have a width divisible by
        ///                 16, and a height 6 times @base_size
        /// @regions        top-left coordinates of each LOD region in order
        pub fn FontAddAsciiMono(
            self: *FontRendererT,
            bmp: []const u8,
            base_size: u32,
            base_advance: f32,
            base_area: Vec2,
            regions: []const Vec2,
        ) usize {
            assert(std.math.isPowerOfTwo(base_size));
            assert(@as(u32, @intFromFloat(base_area.x)) % @as(u32, 16) == 0);
            assert(@as(u32, @intFromFloat(base_area.y)) == base_size * 6);
            assert(regions.len > 0);

            const texture = self.TextureAdd(bmp);
            if (texture == maxInt(usize)) return maxInt(usize);
            assert(self.BufTex[texture].w > 0);
            assert(self.BufTex[texture].h > 0);
            const tw_f = @as(f32, @floatFromInt(self.BufTex[texture].w));
            const th_f = @as(f32, @floatFromInt(self.BufTex[texture].h));

            var this_size = base_size;
            var this_advance = base_advance;
            var this_area_w = @as(u32, @intFromFloat(base_area.x));
            var this_area_h = @as(u32, @intFromFloat(base_area.y));
            for (0..regions.len) |ri| {
                assert(regions[ri].x >= 0);
                assert(regions[ri].y >= 0);
                assert(tw_f >= regions[ri].x + @as(f32, @floatFromInt(this_area_w)));
                assert(th_f >= regions[ri].y + @as(f32, @floatFromInt(this_area_h)));

                const step_x = this_area_w / 16;
                const step_y = this_area_h / 6;
                for (0..96) |gi| {
                    const glyph = self.GlyphAdd(this_advance, .{
                        .x = regions[ri].x + @as(f32, @floatFromInt(step_x * (gi % 16))),
                        .y = regions[ri].y + @as(f32, @floatFromInt(step_y * (gi / 16))),
                        .w = @as(f32, @floatFromInt(step_x)),
                        .h = @as(f32, @floatFromInt(step_y)),
                    });
                    if (glyph == maxInt(usize)) return maxInt(usize);
                }
                const lod = self.FontLODAdd(texture, self.BufGlyCount - 96, 96, this_size);
                if (lod == maxInt(usize)) return maxInt(usize);

                this_size *= 2;
                this_advance *= 2;
                this_area_w *= 2;
                this_area_h *= 2;
            }

            return self.FontAdd(0x20, 0x7F, self.BufLODCount - regions.len, regions.len);
        }

        //-----------------------------
        // usage code

        // NOTE: usage code below assumes that the resources were "allocated"
        //  correctly, as long as the input handle is valid, due to the aggressive
        //  null handle usage in the setup code. in other words, a valid handle
        //  implies there will be no invalid dependent handles in correct usage.
        //  if any failed assertions arise, prefer fixing the setup code above.
        // TODO: use CharSize??

        pub fn DrawString(self: *FontRendererT, font_config: usize, str: []const u8, pos: *const Vec2) void {
            if (font_config >= self.BufStyCount) return;
            const config = &self.BufSty[font_config];
            const font_lod = &self.BufLOD[self.ResolveLOD(font_config)];
            const font = &self.BufFnt[self.BufSty[font_config].Font];

            assert(font.CodepointMax < 0x80); // NOTE: assuming ascii for now, refactor later
            assert(std.mem.min(u8, str) >= @as(u8, @truncate(font.CodepointMin)));
            assert(std.mem.max(u8, str) <= @as(u8, @truncate(font.CodepointMax)));

            const scaling = config.Size / @as(f32, @floatFromInt(font_lod.Size));
            const glyphs = self.BufGly[font_lod.GlyphStart .. font_lod.GlyphStart + font_lod.GlyphCount];
            var rolling_pos = pos.*;
            for (str) |char| {
                const n = char - @as(u8, @truncate(font.CodepointMin));
                const size = glyphs[n].PixelRegion.toSize().MULS(scaling);
                const advance = glyphs[n].AdvanceX * scaling;
                const offset = (advance - size.x) / 2;
                SDLEP(c.SDL_RenderTexture(
                    self.Renderer,
                    self.BufTex[font_lod.Pixels],
                    @ptrCast(&glyphs[n].PixelRegion),
                    &.{ .x = rolling_pos.x + offset, .y = pos.y, .w = size.x, .h = size.y },
                ));

                rolling_pos.x += advance;
            }
        }

        pub fn MeasureString(self: *const FontRendererT, font_config: usize, str: []const u8) Vec2 {
            if (font_config >= self.BufStyCount) return .zero;
            const config = &self.BufSty[font_config];
            const font_lod = &self.BufLOD[self.ResolveLOD(font_config)];
            const font = &self.BufFnt[self.BufSty[font_config].Font];

            assert(font.CodepointMax < 0x80); // NOTE: assuming ascii for now, refactor later
            assert(std.mem.min(u8, str) >= @as(u8, @truncate(font.CodepointMin)));
            assert(std.mem.max(u8, str) <= @as(u8, @truncate(font.CodepointMax)));

            const scaling = config.Size / @as(f32, @floatFromInt(font_lod.Size));
            const glyphs = self.BufGly[font_lod.GlyphStart .. font_lod.GlyphStart + font_lod.GlyphCount];
            return .{
                .x = blk: {
                    var w: f32 = 0;
                    for (str) |char| w += glyphs[char - @as(u8, @truncate(font.CodepointMin))].AdvanceX;
                    break :blk w * scaling;
                },
                .y = @as(f32, @floatFromInt(font_lod.Size)) * scaling,
            };
        }

        pub fn ResolveLOD(self: *const FontRendererT, font_config: usize) usize {
            if (font_config >= self.BufStyCount) return maxInt(usize);
            const config = &self.BufSty[font_config];
            const font = &self.BufFnt[config.Font];

            // LODs are asserted to have sequential power of 2 sizes upon font creation
            const base_log2 = log2_int_ceil(usize, self.BufLOD[font.LODStart].Size);
            return font.LODStart + clamp(
                log2_int_ceil(usize, @as(usize, @intFromFloat(config.Size))),
                base_log2,
                base_log2 + font.LODCount - 1,
            ) - base_log2;
        }

        // TODO: use alpha from input color
        pub fn SetColor(self: *FontRendererT, font_config: usize, color: u32) void {
            if (font_config >= self.BufStyCount) return;
            const rgba = Color.fromInt(color);
            const texture_handle = self.BufLOD[self.ResolveLOD(font_config)].Pixels;
            SDLEP(c.SDL_SetTextureColorMod(self.BufTex[texture_handle], rgba.r, rgba.g, rgba.b));
        }
    };
}

const FontLOD = struct {
    Pixels: usize, // handle to bitmap resource (currently: GPU-allocated texture)
    GlyphStart: usize, // handle to starting glyph in glyph buffer
    GlyphCount: usize,
    Size: usize, // nominal vertical size of the glyphs, also used as line height
};

const Font = struct {
    CodepointMin: u21,
    CodepointMax: u21,
    LODStart: usize, // handle to lowest LOD
    LODCount: usize,
};

const Glyph = struct {
    //Codepoint: u21, // not needed for now, because it's assumed glyph ranges have all codepoints in order
    AdvanceX: f32,
    PixelRegion: Rect,
};

/// this is what is used to actually define a drawable font; handles to these
/// are passed around for use in "draw string" actions
const FontStyle = struct {
    Font: usize, // handle to underlying font definition
    Size: f32, // realized font height; appropriate LOD and scaling calculated at draw time
};

//------------------------------------------------------------------------------

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
    tex_corners: [NUM_CNR_SHAPES - 1][NUM_LOD_LEVELS]CornerTexture, // 4, 8, 16 and 32px radii
    fonts: FontRenderer(NUM_FONTS, 8, NUM_FONTS * 3, NUM_FONTS * 3 * 96, NUM_FONTS * 3),

    const NUM_LOD_LEVELS = 4;
    const NUM_CNR_SHAPES = 7;
    const NUM_FONTS = 4;
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
        .fonts = undefined,
    };

    pub fn Init(alloc: Allocator) !RenderData {
        var rd: RenderData = .empty;

        SDLE(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
        try SDLE(c.SDL_CreateWindowAndRenderer("GU", WINDOW_W, WINDOW_H, 0, &rd.window, &rd.renderer));

        comptime assert(CNR_PX_LODS.len == NUM_CNR_SHAPES - 1);
        for (0..NUM_CNR_SHAPES - 1) |ci| {
            comptime assert(CNR_PX_LODS[ci].len == NUM_LOD_LEVELS);
            for (0..NUM_LOD_LEVELS) |li| {
                const width = pow(i32, 2, @as(i32, @intCast(li)) + 2) * 2;
                rd.tex_corners[ci][li] = try .Init(rd.renderer, width, CNR_PX_LODS[ci][li]);
            }
        }

        rd.fonts = try .Init(alloc, rd.renderer);

        errdefer comptime unreachable;
        SDLEP(c.SDL_SetRenderDrawBlendMode(rd.renderer, c.SDL_BLENDMODE_BLEND));
        SDLE(c.SDL_SetWindowResizable(rd.window, true)) catch {};

        return rd;
    }

    pub fn Deinit(self: *RenderData, alloc: Allocator) void {
        for (0..NUM_CNR_SHAPES - 1) |ci| for (0..NUM_LOD_LEVELS) |li| self.tex_corners[ci][li].Deinit();
        self.fonts.Deinit(alloc);
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
    }

    // BACKEND

    fn fn_surface_size(ptr: *anyopaque) Vec2 {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        var screen_w: c_int = undefined;
        var screen_h: c_int = undefined;
        SDLEP(c.SDL_GetRenderOutputSize(self.renderer, &screen_w, &screen_h));
        return Vec2{ .x = @floatFromInt(screen_w), .y = @floatFromInt(screen_h) };
    }

    fn fn_clip_set(ptr: *anyopaque, cmd: *const GURCClip) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        const rect = c.SDL_Rect{
            .x = @as(c_int, @intFromFloat(cmd.area.x)),
            .y = @as(c_int, @intFromFloat(cmd.area.y)),
            .w = @as(c_int, @intFromFloat(cmd.area.w)),
            .h = @as(c_int, @intFromFloat(cmd.area.h)),
        };
        SDLEP(c.SDL_SetRenderClipRect(self.renderer, &rect));
    }

    fn fn_clip_get(ptr: *anyopaque) Rect {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        if (self.stored_clip) |*clip| {
            return Rect{
                .x = @as(f32, @floatFromInt(clip.x)),
                .y = @as(f32, @floatFromInt(clip.y)),
                .w = @as(f32, @floatFromInt(clip.w)),
                .h = @as(f32, @floatFromInt(clip.h)),
            };
        }
        const sd = fn_surface_size(ptr);
        return Rect{ .x = 0, .y = 0, .w = sd.w, .h = sd.h };
    }

    // TODO: respect corner shape/radius def in cmd
    fn fn_custom_command_emit(ptr: *anyopaque, cmd: *const GURCCustom) void {
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

    fn fn_rect_draw(ptr: *anyopaque, cmd: *const GURCRect) void {
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
        assert(cmd.corner_shape < NUM_CNR_SHAPES);
        const dst_size: f32 = @min(@floor(@min(cmd.rect.w, cmd.rect.h) / 2), cmd.corner_radius);

        const tex_lod_index: usize =
            clamp(log2_int_ceil(usize, @intFromFloat(dst_size)), 2, 2 + NUM_LOD_LEVELS - 1) - 2;
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

    fn fn_string_draw(ptr: *anyopaque, cmd: *const GURCText) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        self.fonts.SetColor(cmd.font, cmd.color);
        self.fonts.DrawString(cmd.font, cmd.str, &cmd.pos);
    }

    fn fn_string_size(ptr: *anyopaque, font: GUFontHandle, str: []const u8) Vec2 {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        return self.fonts.MeasureString(font, str);
    }

    fn fn_render_begin(ptr: *anyopaque) void {
        const self: *RenderData = @ptrCast(@alignCast(ptr));
        assert(self.stored_clip == null);
        if (c.SDL_RenderClipEnabled(self.renderer)) {
            var clip: c.SDL_Rect = undefined;
            SDLEP(c.SDL_GetRenderClipRect(self.renderer, &clip));
            self.stored_clip = clip;
        }
    }

    fn fn_render_end(ptr: *anyopaque) void {
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
            .fnSurfaceSize = fn_surface_size,
            .fnCustomCommandEmit = fn_custom_command_emit,
            .fnRectDraw = fn_rect_draw,
            .fnStringDraw = fn_string_draw,
            .fnStringSize = fn_string_size,
            .fnClipSet = fn_clip_set,
            .fnRenderBegin = fn_render_begin,
            .fnRenderEnd = fn_render_end,
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
    .padding = .init(9, 9),
    .gaps = .init(6, 6),
    .auto_line_break = false,
    .corner_radius = 0,
    .corner_shape = RenderData.CNR_RECT,
};

const LAYOUT_RED = std.mem.zeroInit(GULayout, .{
    .color = 0x80000060,
});

const LAYOUT_WHITE = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .padding = Vec2.init(4, 4),
    .corner_radius = 8,
    .corner_shape = RenderData.CNR_ROUND,
});

const LAYOUT_WHITE_BREAK = std.mem.zeroInit(GULayout, .{
    .color = 0xFFFFFF20,
    .auto_line_break = true,
    .padding = Vec2.init(4, 4),
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
    .PaddingVer = 1,
    .PaddingHor = 8,
    .CornerRad = 6,
    .CornerShape = RenderData.CNR_ROUND,
    .ColorIdle = 0x008000FF,
    .ColorHover = 0x00C000FF,
    .ColorDown = 0x004000FF,
};

const FONT_BODY: GUFontHandle = 0;

const BASE_FONT = FONT_BODY;

//------------------------------------------------------------------------------

const App = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    alloc: std.mem.Allocator,

    rd: RenderData,
    gu: GU,

    textures: [2]ImageTexture,
    texture_handles: [2]GUTextureHandle,

    fonts: [1]usize,
    font_styles: [1]usize,

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

    app_global.rd = RenderData.Init(alloc) catch |e|
        std.debug.panic("initializing RenderData failed: {s}", .{@errorName(e)});

    // UI-RELATED

    app_global.gu = GU.Init(alloc, app_global.rd.GetBackend(), BASE_LAYOUT, BASE_BUTTON_STYLE, BASE_FONT);

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

    for (&FONTS, 0..) |*fd, i|
        app_global.fonts[i] = app_global.rd.fonts.FontAddAsciiMono(fd.@"0", fd.@"1", fd.@"2", fd.@"3", fd.@"4");

    for (&FONT_STYLES, 0..) |*fs, i|
        app_global.font_styles[i] = app_global.rd.fonts.StyleAdd(fs.@"0", fs.@"1");

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
        gu.SetNextButtonMode(.Release);
        if (gu.DoButton("ReleaseButton", .{}))
            app.btn_color_loop = (app.btn_color_loop + 1) % color_loop.len;
        gu.DoLineBreak();
        gu.DoImage(img1, color_loop[app.btn_color_loop], 0.1);
    }

    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();

        gu.DoLabel(0xC000C0FF, "testblock2", .{});
        if (gu.DoToggleButton(&app.btn_toggle, "ToggleButton: {any}", .{app.btn_toggle})) {}
        if (app.btn_toggle) gu.DoLabel(null, "only visible if b2 is on", .{});
        gu.DoImage(img2, 0xC000C0FF, 0.15);
        gu.DoImage(img1, null, 0.15);
    }

    if (gu.DoElement(&LAYOUT_WHITE)) {
        defer gu.EndElement();
        gu.SetElementGaps(4, 4);

        gu.DoLineBreak();
        gu.PushButtonPadding(12, 2);
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
        if (gu.DoToggleButton(&app.btn_toggle, "ToggleButton", .{})) {}

        gu.DoLineBreak();
        gu.DoImage(img1, null, 0.35);
        gu.DoImage(img2, null, 0.35);

        gu.DoLineBreak();
        if (app.btn_toggle) gu.DoLabelsFromString("only visible if b2 is on.");
        gu.DoLabelsFromString("The quick, brown fox jumps over a lazy dog. DJs flock by when MTV ax quiz prog. Junk MTV quiz graced by fox whelps. Bawds jog, flick quartz, vex nymphs. Waltz, bad nymph, for quick jigs vex! Fox nymphs grab quick-jived waltz. Brick quiz whangs jumpy veldt fox. Bright vixens jump; dozy fowl quack. Quick wafting zephyrs vex bold Jim. Quick zephyrs blow, vexing daft Jim. Sex-charged fop blew my junk TV quiz. How quickly daft jumping zebras vex.\nTwo driven jocks help fax my big quiz. Quick, Baz, get my woven flax jodhpurs! \"Now fax quiz Jack!\" my brave ghost pled. Five quacking zephyrs jolt my wax bed. Flummoxed by job, kvetching W. zaps Iraq. Cozy sphinx waves quart jug of bad milk. A very bad quack might jinx zippy fowls. Few quips galvanized the mock jury box. Quick brown dogs jump over the lazy fox. The jay, pig, fox, zebra, and my wolves quack! Blowzy red vixens fight for a quick jump. Joaquin Phoenix was gazed by MTV for luck. A wizard's job is to vex chumps quickly in fog. Watch \"Jeopardy!\", Alex Trebek's fun TV quiz game. Woven silk pyjamas exchanged for blue quartz.");
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

        const fnt_ptr = &app.rd.fonts.BufSty[FONT_BODY];
        gu.DoLineBreak();
        gu.SetNextButtonColor(0x800000FF, 0xC00000FF, 0x400000FF);
        if (gu.DoButton("Font DN", .{})) fnt_ptr.Size = @max(1, fnt_ptr.Size - 1);
        if (gu.DoButton("Font UP", .{})) fnt_ptr.Size += 1;
        gu.DoLineBreak();
        gu.DoLabel(0xCCCCFFFF, "{d:0>3}", .{fnt_ptr.Size});

        const new_font_lod = app.rd.fonts.ResolveLOD(FONT_BODY);
        gu.DoLineBreak();
        gu.DoLabel(0xCCCCFFFF, "LOD: {d}", .{new_font_lod});

        const measure_size = app.rd.fonts.MeasureString(FONT_BODY, "Measure");
        gu.DoLineBreak();
        gu.DoLabel(0xCCCCFFFF, "\"Measure\" Size:", .{});
        gu.DoLineBreak();
        gu.DoLabel(0xCCCCFFFF, "  {d:3.1} x {d:3.1}", .{ measure_size.x, measure_size.y });
    }

    gu.EndFrame();

    SDLEP(c.SDL_RenderPresent(rd.renderer));

    return c.SDL_APP_CONTINUE;
}

pub export fn SDL_AppQuit(app: *App, _: c.SDL_AppResult) void {
    app.gu.Deinit();
    app.rd.Deinit(app.alloc); // FIXME: don't like this alloc so much
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    _ = c.SDL_main(@intCast(args.len), @ptrCast(args.ptr));
}
