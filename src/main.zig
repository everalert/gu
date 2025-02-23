const std = @import("std");

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const GU = @import("gu.zig");
const GURect = GU.GURect;
const GUPos = GU.GUPos;

const WINDOW_W = 800;
const WINDOW_H = 600;

const FONT = @embedFile("ascii-font");

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

    const window: ?*c.SDL_Window, const renderer: ?*c.SDL_Renderer = create_window_and_renderer: {
        var w: ?*c.SDL_Window = undefined;
        var r: ?*c.SDL_Renderer = undefined;
        SDLE(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
        try SDLE(c.SDL_CreateWindowAndRenderer("GU", WINDOW_W, WINDOW_H, 0, &w, &r));
        errdefer comptime unreachable;
        break :create_window_and_renderer .{ w, r };
    };
    defer c.SDL_DestroyRenderer(renderer);
    defer c.SDL_DestroyWindow(window);

    // UI-RELATED SETUP

    var gu = GU.Init(alloc);
    defer gu.Deinit();

    const ascii_font: *c.SDL_Texture = load_ascii_font: {
        const stream: *c.SDL_IOStream = try SDLE(c.SDL_IOFromConstMem(FONT, FONT.len));
        const surface: *c.SDL_Surface = try SDLE(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);
        const texture: *c.SDL_Texture = try SDLE(c.SDL_CreateTextureFromSurface(renderer, surface));
        errdefer comptime unreachable;
        break :load_ascii_font texture;
    };
    defer c.SDL_DestroyTexture(ascii_font);
    const font_id = try gu.AddFont(ascii_font);
    const img_id = try gu.AddImage(ascii_font);

    var mouse = Mouse{};
    var b1 = GUButton{ .rect = .{ .x = 10, .y = 30, .w = 64, .h = 32 } };

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
                    mouse.pt.x = event.motion.x;
                    mouse.pt.y = event.motion.y;
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button != 1) continue;
                    const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
                    mouse.AccumulateButton(down);
                },
                else => {},
            }
        }

        mouse.UpdateButton();

        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x22, 0xFF));
        try SDLE(c.SDL_RenderClear(renderer));

        gu.BeginFrame();

        try gu.DoRect(0, 0, 400, 600, 0x000055FF);
        try gu.DoRect(400, 0, 400, 600, 0x2222AAFF); // outline color

        try gu.DoLabel(10, 10, font_id, 0xC00000FF, "testing... !!@$(#!QOIEANSHT)");
        try gu.DoLabel(256, 10, null, 0x00C000FF, "testing... !!@$(#!QOIEANSHT)");

        // WARN: currently drawn over during render command parsing stage
        if (try b1.DrawButton(renderer, &mouse)) {
            std.log.debug("button1 activated!!", .{});
        }

        try gu.DoImage(10, 72, img_id, 0x00C000FF);
        try gu.DoImage(256, 72, img_id, null);

        //gu.EndFrame

        for (gu.render_commands.items) |command| {
            switch (command) {
                .Rect => |rect| try DrawRect(renderer, &rect.rect, rect.color, null),
                .Text => |text| try DrawString(renderer, text.font, &text.pos, text.str, text.color),
                .Image => |img| try DrawImage(renderer, img.image, &img.pos, img.color),
            }
        }

        try SDLE(c.SDL_RenderPresent(renderer));
    }
}

const Mouse = struct {
    pt: c.SDL_FPoint = .{ .x = -100, .y = -100 },
    btn: bool = false,
    btn_just_up: bool = false,
    btn_just_down: bool = false,
    btn_acc_down: bool = false,
    btn_acc_changes: u32 = 0,

    fn AccumulateButton(self: *Mouse, down: bool) void {
        if (self.btn_acc_down != down) {
            self.btn_acc_down = down;
            self.btn_acc_changes += 1;
        }
    }

    fn UpdateButton(self: *Mouse) void {
        self.btn_just_down = (self.btn_acc_down and self.btn_acc_down != self.btn) or (self.btn_acc_changes > 1);
        self.btn_just_up = (!self.btn_acc_down and self.btn_acc_down != self.btn) or (self.btn_acc_changes > 1);
        self.btn = self.btn_acc_down;
        self.btn_acc_changes = 0;
    }
};

// NOTE: temporary abstraction that will later be translated to ui system
const GUButton = struct {
    mode: enum(u32) { Press, Release } = .Press,
    state: enum(u32) { Idle, Hover, Down } = .Idle,
    rect: c.SDL_FRect,

    /// returns whether button was 'activated' (pressed)
    fn DrawButton(self: *GUButton, renderer: ?*c.SDL_Renderer, mouse: *Mouse) !bool {
        var output = false;
        const is_mouseover = c.SDL_PointInRectFloat(&mouse.pt, &self.rect);
        if (is_mouseover) {
            if (self.state == .Idle)
                self.state = .Hover;

            if (self.state == .Hover and mouse.btn_just_down) {
                self.state = .Down;
                if (self.mode == .Press) {
                    std.log.debug("button pressed!", .{});
                    output = true;
                }
            }

            if (self.state == .Down and mouse.btn_just_up) {
                self.state = .Hover;
                if (self.mode == .Release) {
                    std.log.debug("button released!", .{});
                    output = true;
                }
            }
        } else {
            self.state = .Idle;
        }

        // TODO: move to dedicated render pass
        switch (self.state) {
            .Idle => try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x80, 0x00, 0xFF)),
            .Hover => try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0xC0, 0x00, 0xFF)),
            .Down => try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x40, 0x00, 0xFF)),
        }
        try SDLE(c.SDL_RenderFillRect(renderer, &self.rect));

        return output;
    }
};

// TODO: use alpha from input color
fn DrawString(renderer: ?*c.SDL_Renderer, texture: *anyopaque, pos: *const GUPos, str: []const u8, color: ?u32) !void {
    std.debug.assert(std.mem.min(u8, str) >= ' ');
    std.debug.assert(std.mem.max(u8, str) < 127);
    const tex: *c.SDL_Texture = @alignCast(@ptrCast(texture));
    var rgba = [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    if (color) |col| rgba = .{ @truncate(col >> 24), @truncate(col >> 16), @truncate(col >> 8), 0xFF };
    try SDLE(c.SDL_SetTextureColorMod(tex, rgba[0], rgba[1], rgba[2]));
    var rolling_x = pos.x;
    var rolling_y = pos.y;
    for (str) |char|
        try DrawChar(renderer, tex, &rolling_x, &rolling_y, char);
}

fn DrawChar(renderer: ?*c.SDL_Renderer, texture: *c.SDL_Texture, x: *f32, y: *f32, char: u8) !void {
    std.debug.assert(char >= ' ');
    std.debug.assert(char < 127);
    const num_w: f32 = 10;
    const num_h: f32 = 21;
    const n = char - ' ';
    const i: f32 = @as(f32, @floatFromInt(n % 16)) * num_w;
    const j: f32 = @as(f32, @floatFromInt(n / 16)) * num_h;
    try SDLE(c.SDL_RenderTexture(
        renderer,
        texture,
        &.{ .x = i, .y = j, .w = num_w, .h = num_h },
        &.{ .x = x.*, .y = y.*, .w = num_w, .h = num_h },
    ));
    x.* += num_w;
}

// TODO: use alpha from input color
fn DrawImage(renderer: ?*c.SDL_Renderer, texture: *anyopaque, pos: *const GUPos, color: ?u32) !void {
    const tex: *c.SDL_Texture = @alignCast(@ptrCast(texture));
    var rgba = [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    if (color) |col| rgba = .{ @truncate(col >> 24), @truncate(col >> 16), @truncate(col >> 8), 0xFF };
    try SDLE(c.SDL_SetTextureColorMod(tex, rgba[0], rgba[1], rgba[2]));
    try SDLE(c.SDL_RenderTexture(renderer, tex, null, &.{
        .x = pos.x,
        .y = pos.y,
        .w = @floatFromInt(tex.w),
        .h = @floatFromInt(tex.h),
    }));
}

fn DrawRect(renderer: ?*c.SDL_Renderer, rect: *const GURect, color: u32, outline_color: ?u32) !void {
    const c1 = [4]u8{ @truncate(color >> 24), @truncate(color >> 16), @truncate(color >> 8), @truncate(color) };
    try SDLE(c.SDL_SetRenderDrawColor(renderer, c1[0], c1[1], c1[2], c1[3]));
    try SDLE(c.SDL_RenderFillRect(renderer, &.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }));
    if (outline_color) |col| {
        try SDLE(c.SDL_SetRenderDrawColor(
            renderer,
            @truncate(col >> 24),
            @truncate(col >> 16),
            @truncate(col >> 8),
            @truncate(col),
        ));
        try SDLE(c.SDL_RenderRect(renderer, &.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }));
    }
}
