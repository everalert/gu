const std = @import("std");

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLEP = @import("c.zig").SDLEP;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const GU = @import("gu.zig");
const GUBackend = GU.GUBackend;
const GURect = GU.GURect;
const GUPos = GU.GUPos;
const GUSize = GU.GUSize;
const GUColor = GU.GUColor;
const GUTextureAtlas = GU.GUTextureAtlas;
const GUFontAtlas = GU.GUFontAtlas;
const GUButton = GU.GUButton;
const GULayout = GU.GULayout;

const WINDOW_W = 800;
const WINDOW_H = 600;

const FONT = @embedFile("ascii-font");

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
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        const rgba = GUColor.FromInt(color);
        SDLEP(c.SDL_SetTextureColorMod(self.texture, rgba.r, rgba.g, rgba.b));
    }

    // FONT RELATED

    // TODO: use CharSize
    fn StringSize(_: *anyopaque, str: []const u8) GUSize {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        std.debug.assert(std.mem.min(u8, str) >= ' ');
        std.debug.assert(std.mem.max(u8, str) < 127);
        return .{ .w = 10 * @as(f32, @floatFromInt(str.len)), .h = 21 };
    }

    // TODO: use data table/mapping for individual char data
    fn CharSize(_: *anyopaque, _: u8) GUSize {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return GUSize{ .w = 10, .h = 21 };
    }

    fn DrawString(ptr: *anyopaque, str: []const u8, pos: *const GUPos) void {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        std.debug.assert(std.mem.min(u8, str) >= ' ');
        std.debug.assert(std.mem.max(u8, str) < 127);
        var rolling_pos = pos.*;
        for (str) |char| {
            DrawChar(ptr, char, &rolling_pos);
            rolling_pos.x += CharSize(self, char).w;
        }
    }

    fn DrawChar(ptr: *anyopaque, char: u8, pos: *const GUPos) void {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        std.debug.assert(char >= ' ');
        std.debug.assert(char < 127);
        const size = CharSize(ptr, char);
        const n = char - ' ';
        const i: f32 = @as(f32, @floatFromInt(n % 16)) * size.w;
        const j: f32 = @as(f32, @floatFromInt(n / 16)) * size.h;
        SDLEP(c.SDL_RenderTexture(
            self.renderer,
            self.texture,
            &.{ .x = i, .y = j, .w = size.w, .h = size.h },
            &.{ .x = pos.x, .y = pos.y, .w = size.w, .h = size.h },
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

    // TEXTURE RELATED

    fn Draw(ptr: *anyopaque, pos: *const GUPos) void {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        const size = Size(ptr);
        SDLEP(c.SDL_RenderTexture(
            self.renderer,
            self.texture,
            null,
            &.{ .x = pos.x, .y = pos.y, .w = size.w, .h = size.h },
        ));
    }

    fn DrawTile(ptr: *anyopaque, id: u32, pos: *const GUPos) void {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        DrawChar(ptr, @truncate(id), pos);
    }

    fn Size(ptr: *anyopaque) GUSize {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return GUSize{ .w = @floatFromInt(self.texture.w), .h = @floatFromInt(self.texture.h) };
    }

    fn TileSize(ptr: *anyopaque, id: u32) GUSize {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return CharSize(ptr, @truncate(id));
    }

    pub fn GetTextureAtlas(self: *AsciiFont) GUTextureAtlas {
        return GUTextureAtlas{
            .ptr = self,
            .fnDraw = Draw,
            .fnDrawTile = DrawTile,
            .fnSize = Size,
            .fnTileSize = TileSize,
            .fnSetColor = SetColor,
        };
    }
};

const RenderData = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,

    pub fn Init() !RenderData {
        var w: ?*c.SDL_Window = undefined;
        var r: ?*c.SDL_Renderer = undefined;
        SDLE(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
        try SDLE(c.SDL_CreateWindowAndRenderer("GU", WINDOW_W, WINDOW_H, 0, &w, &r));
        errdefer comptime unreachable;
        SDLEP(c.SDL_SetRenderDrawBlendMode(r, c.SDL_BLENDMODE_BLEND));
        SDLE(c.SDL_SetWindowResizable(w, true)) catch {};
        return RenderData{ .window = w, .renderer = r };
    }

    pub fn Deinit(self: *RenderData) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
    }

    // BACKEND

    fn GetSurfaceDimensions(ptr: *anyopaque) GUSize {
        const self: *RenderData = @alignCast(@ptrCast(ptr));
        var screen_w: c_int = undefined;
        var screen_h: c_int = undefined;
        SDLEP(c.SDL_GetRenderOutputSize(self.renderer, &screen_w, &screen_h));
        return GUSize{ .w = @floatFromInt(screen_w), .h = @floatFromInt(screen_h) };
    }

    fn DrawString(_: *anyopaque, font: *GUFontAtlas, pos: *const GUPos, str: []const u8, color: u32) void {
        //const self: *RenderData = @alignCast(@ptrCast(ptr));
        font.SetColor(color);
        font.DrawString(str, pos);
    }

    fn DrawImage(_: *anyopaque, image: *GUTextureAtlas, pos: *const GUPos, color: u32) void {
        //const self: *RenderData = @alignCast(@ptrCast(ptr));
        image.SetColor(color);
        image.Draw(pos);
    }

    fn DrawRect(ptr: *anyopaque, rect: *const GURect, color: u32) void {
        const self: *RenderData = @alignCast(@ptrCast(ptr));
        const c1 = GUColor.FromInt(color);
        SDLEP(c.SDL_SetRenderDrawColor(self.renderer, c1.r, c1.g, c1.b, c1.a));
        SDLEP(c.SDL_RenderFillRect(self.renderer, &.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }));
        //if (outline_color) |col| {
        //    const c2 = GUColor.FromInt(col);
        //    SDLEP(c.SDL_SetRenderDrawColor(self.renderer, c2.r, c2.g, c2.b, c2.a));
        //    SDLEP(c.SDL_RenderRect(self.renderer, &.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }));
        //}
    }

    pub fn GetBackend(self: *RenderData) GUBackend {
        return GUBackend{
            .ptr = self,
            .fnGetSurfaceDimensions = GetSurfaceDimensions,
            .fnDrawRect = DrawRect,
            .fnDrawImage = DrawImage,
            .fnDrawString = DrawString,
        };
    }
};

pub fn main() !void {
    errdefer |err| SDLTryErrorPrint(@errorName(err));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // SDL INIT

    c.SDL_SetMainReady();
    try SDLE(c.SDL_SetAppMetadata("GU", "0.0.0", "com.galeforce.gu"));
    try SDLE(c.SDL_Init(c.SDL_INIT_VIDEO));
    defer c.SDL_Quit();

    // SDL VIDEO INIT

    var rd = try RenderData.Init();
    defer rd.Deinit();

    // UI-RELATED SETUP

    const base_layout = GULayout{
        .mode_w = .Auto,
        .mode_h = .Auto,
        .color = 0xFFFFFF40,
        .widths = &[_]f32{ 200, -400, 200 },
        .heights = &[_]f32{ 100, 200 },
        .padding = GUSize{ .w = 8, .h = 8 },
        .gaps = GUSize{ .w = 8, .h = 8 },
    };
    const layout_red = std.mem.zeroInit(GULayout, .{
        .color = 0x80000060,
    });
    const layout_white = std.mem.zeroInit(GULayout, .{
        .color = 0xFFFFFF40,
    });

    var gu = GU.Init(alloc, rd.GetBackend(), base_layout);
    defer gu.Deinit();

    var font = try AsciiFont.Init(rd.renderer, FONT);
    defer font.Deinit();
    const font_id = try gu.AddFont(font.GetFontAtlas());
    const img_id = try gu.AddImage(font.GetTextureAtlas());

    var step: bool = true;

    // MAIN LOOP

    var quit = false;
    var event: c.SDL_Event = undefined;
    while (!quit) quit: {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    quit = true;
                    break :quit;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    gu.mouse_pt.x = event.motion.x;
                    gu.mouse_pt.y = event.motion.y;
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button != c.SDL_BUTTON_LEFT) continue;
                    const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
                    gu.mouse_left.Accumulate(down);
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == c.SDL_SCANCODE_RETURN)
                        step = true;
                },
                else => {},
            }
        }

        // NOTE: frame advance helper for debugging
        //if (!step) continue;
        //step = false;

        try SDLE(c.SDL_SetRenderDrawColor(rd.renderer, 0x00, 0x00, 0x22, 0xFF));
        try SDLE(c.SDL_RenderClear(rd.renderer));

        try gu.BeginFrame();

        // old stuff

        // NOTE: using base layout to reproduce child block row resolution bug;
        // remove DoNewLine to check elements wrap as expected
        //if (gu.StartLayoutBlock(&base_layout)) {
        if (gu.StartLayoutBlock(null)) {
            defer gu.EndLayoutBlock();

            try gu.DoLabel(null, 0x00C000FF, "testblock1");

            gu.DoNewLine();
            try gu.DoRect(76, 25, 0x008000FF); // was button 1

            gu.DoNewLine();
            try gu.DoImage(img_id, 0x00C000FF);
            gu.DoNewLine();
            try gu.DoImage(img_id, null);
        }

        if (gu.StartLayoutBlock(null)) {
            defer gu.EndLayoutBlock();

            try gu.DoLabel(null, 0xC000C0FF, "testblock2");

            gu.DoNewLine();
            try gu.DoRect(76, 25, 0x008000FF); // was button 2

            gu.DoNewLine();
            try gu.DoImage(img_id, 0xC000C0FF);
            gu.DoNewLine();
            try gu.DoImage(img_id, null);
        }

        if (gu.StartLayoutBlock(null)) {
            defer gu.EndLayoutBlock();

            try gu.DoRect(64, 64, 0x000055FF);

            gu.DoNewLine();
            //gu.NextElementOverridePosition(.{ .x = 10, .y = 10 });
            try gu.DoLabel(font_id, 0xC00000FF, "testblock3");

            gu.DoNewLine();
            try gu.DoRect(64, 64, 0x2222AAFF); // old outline color
        }

        try gu.DoLabel(null, 0x0000C0FF, "testing... !!@$(#!QOIEANSHT)");

        try gu.DoLabel(null, 0x00C0C0FF, "testing... !!@$(#!QOIEANSHT)");

        try gu.DoLabel(null, 0xC0C000FF, "testing... !!@$(#!QOIEANSHT)");

        // new stuff

        //if (gu.DoContainer(&base_layout)) {
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            if (gu.DoContainer(&layout_red)) {
                defer gu.EndContainer();
                gu.DoLabelNEW(null, 0x00C000FF, "testblock1");
            }
            gu.DoLineBreak();
            if (gu.DoContainer(&layout_red)) {
                defer gu.EndContainer();
                if (gu.DoButtonNEW(font_id, "Button")) {
                    std.log.debug("b1 activation result!!", .{});
                }
            }
            gu.DoLineBreak();
            if (gu.DoContainer(&layout_red)) {
                defer gu.EndContainer();
                gu.DoImageNEW(img_id, 0x00C000FF);
            }
            gu.DoLineBreak();
            if (gu.DoContainer(&layout_red)) {
                defer gu.EndContainer();
                gu.DoImageNEW(img_id, null);
            }
        }
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            gu.DoLabelNEW(null, 0xC000C0FF, "testblock2");
            gu.DoLineBreak();
            if (gu.DoButtonNEW(font_id, "Button")) {
                std.log.debug("b2 activation result!!", .{});
            }
            gu.DoLineBreak();
            gu.DoImageNEW(img_id, 0xC000C0FF);
            gu.DoLineBreak();
            gu.DoImageNEW(img_id, null);
        }
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            gu.DoRectNEW(.{ .w = 64, .h = 64 }, 0x000055FF);
            gu.DoLineBreak();
            //gu.NextElementOverridePosition(.{ .x = 10, .y = 10 });
            gu.DoLabelNEW(font_id, 0xC00000FF, "testblock3");
            gu.DoLineBreak();
            gu.DoRectNEW(.{ .w = 64, .h = 64 }, 0x2222AAFF); // old outline color
        }
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            gu.DoLabelNEW(null, 0x0000C0FF, "testing... !!@$(#!QOIEANSHT)");
        }
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            gu.DoLabelNEW(null, 0x00C0C0FF, "testing... !!@$(#!QOIEANSHT)");
        }
        if (gu.DoContainer(&layout_white)) {
            defer gu.EndContainer();
            gu.DoLabelNEW(null, 0xC0C000FF, "testing... !!@$(#!QOIEANSHT)");
        }

        gu.EndFrame();

        try SDLE(c.SDL_RenderPresent(rd.renderer));
    }
}
