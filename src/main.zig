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
    pub fn SetColor(ptr: *anyopaque, color: u32) void {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        const rgba = GUColor.FromInt(color);
        SDLEP(c.SDL_SetTextureColorMod(self.texture, rgba.r, rgba.g, rgba.b));
    }

    // FONT RELATED

    // TODO: use CharSize
    pub fn StringSize(_: *anyopaque, str: []const u8) GUSize {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        std.debug.assert(std.mem.min(u8, str) >= ' ');
        std.debug.assert(std.mem.max(u8, str) < 127);
        return .{ .w = 10 * @as(f32, @floatFromInt(str.len)), .h = 21 };
    }

    // TODO: use data table/mapping for individual char data
    pub fn CharSize(_: *anyopaque, _: u8) GUSize {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return GUSize{ .w = 10, .h = 21 };
    }

    pub fn DrawString(ptr: *anyopaque, str: []const u8, pos: *const GUPos) void {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        std.debug.assert(std.mem.min(u8, str) >= ' ');
        std.debug.assert(std.mem.max(u8, str) < 127);
        var rolling_pos = pos.*;
        for (str) |char| {
            DrawChar(ptr, char, &rolling_pos);
            rolling_pos.x += CharSize(self, char).w;
        }
    }

    pub fn DrawChar(ptr: *anyopaque, char: u8, pos: *const GUPos) void {
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

    pub fn DrawTile(ptr: *anyopaque, id: u32, pos: *const GUPos) void {
        //const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        DrawChar(ptr, @truncate(id), pos);
    }

    pub fn Size(ptr: *anyopaque) GUSize {
        const self: *AsciiFont = @alignCast(@ptrCast(ptr));
        return GUSize{ .w = @floatFromInt(self.texture.w), .h = @floatFromInt(self.texture.h) };
    }

    pub fn TileSize(ptr: *anyopaque, id: u32) GUSize {
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
        return RenderData{ .window = w, .renderer = r };
    }

    pub fn Deinit(self: *RenderData) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
    }

    // FIXME: remove in favor of GUFontAtlas->StringSize
    pub fn StringSize(str: []const u8) GUSize {
        std.debug.assert(std.mem.min(u8, str) >= ' ');
        std.debug.assert(std.mem.max(u8, str) < 127);
        //_ = @as(*c.SDL_Texture, @alignCast(@ptrCast(texture))); // texture = *anyopaque
        return .{ .w = 10 * @as(f32, @floatFromInt(str.len)), .h = 21 };
    }

    pub fn DrawString(_: *anyopaque, font: *GUFontAtlas, pos: *const GUPos, str: []const u8, color: u32) void {
        //const self: *RenderData = @alignCast(@ptrCast(ptr));
        font.SetColor(color);
        font.DrawString(str, pos);
    }

    pub fn DrawImage(_: *anyopaque, image: *GUTextureAtlas, pos: *const GUPos, color: u32) void {
        //const self: *RenderData = @alignCast(@ptrCast(ptr));
        image.SetColor(color);
        image.Draw(pos);
    }

    pub fn DrawRect(ptr: *anyopaque, rect: *const GURect, color: u32) void {
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

    var backend = GUBackend{
        .ptr = &rd,
        .fnDrawRect = RenderData.DrawRect,
        .fnDrawImage = RenderData.DrawImage,
        .fnDrawString = RenderData.DrawString,
    };

    var gu = GU.Init(alloc, &backend);
    defer gu.Deinit();

    var font = try AsciiFont.Init(rd.renderer, FONT);
    defer font.Deinit();
    const font_id = try gu.AddFont(font.GetFontAtlas());
    const img_id = try gu.AddImage(font.GetTextureAtlas());

    var b1 = GUButton{};

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
                else => {},
            }
        }

        try SDLE(c.SDL_SetRenderDrawColor(rd.renderer, 0x00, 0x00, 0x22, 0xFF));
        try SDLE(c.SDL_RenderClear(rd.renderer));

        gu.BeginFrame();

        try gu.DoRect(0, 0, 400, 600, 0x000055FF);
        try gu.DoRect(400, 0, 400, 600, 0x2222AAFF); // outline color

        try gu.DoLabel(10, 10, font_id, 0xC00000FF, "testing... !!@$(#!QOIEANSHT)");
        try gu.DoLabel(256, 10, null, 0x00C000FF, "testing... !!@$(#!QOIEANSHT)");

        if (try b1.DoButton(10, 32, &gu, "Button")) {
            std.log.debug("b1 activation result!!", .{});
        }

        try gu.DoImage(10, 72, img_id, 0x00C000FF);
        try gu.DoImage(256, 72, img_id, null);

        gu.EndFrame();

        try SDLE(c.SDL_RenderPresent(rd.renderer));
    }
}

// NOTE: temporary abstraction that will later be translated to ui system
const GUButton = struct {
    const PADDING_VERTICAL: f32 = 2;
    const PADDING_HORIZONTAL: f32 = 8;

    mode: enum(u32) { Press, Release } = .Press,
    state: enum(u32) { Idle, Hover, Down } = .Idle,

    // WARN: currently prevented from migrating to GU by StringSize (needs texture atlas interface)
    /// returns whether button was 'activated' (pressed)
    fn DoButton(self: *GUButton, x: f32, y: f32, gu: *GU, str: []const u8) !bool {
        const str_size = RenderData.StringSize(str);
        const rect = GURect{
            .x = x,
            .y = y,
            .w = PADDING_HORIZONTAL * 2 + str_size.w,
            .h = PADDING_VERTICAL * 2 + str_size.h,
        };

        var output = false;
        const is_mouseover = rect.PointInRect(&gu.mouse_pt);
        if (is_mouseover) {
            if (self.state == .Idle)
                self.state = .Hover;

            if (self.state == .Hover and gu.mouse_left.just_down) {
                self.state = .Down;
                if (self.mode == .Press) {
                    std.log.debug("button activated! (press)", .{});
                    output = true;
                }
            }

            if (self.state == .Down and gu.mouse_left.just_up) {
                self.state = .Hover;
                if (self.mode == .Release) {
                    std.log.debug("button activated! (release)", .{});
                    output = true;
                }
            }
        } else {
            self.state = .Idle;
        }

        switch (self.state) {
            .Idle => try gu.DoRect(rect.x, rect.y, rect.w, rect.h, 0x008000FF),
            .Hover => try gu.DoRect(rect.x, rect.y, rect.w, rect.h, 0x00C000FF),
            .Down => try gu.DoRect(rect.x, rect.y, rect.w, rect.h, 0x004000FF),
        }
        try gu.DoLabel(rect.x + PADDING_HORIZONTAL, rect.y + PADDING_VERTICAL, null, null, str);

        return output;
    }
};
