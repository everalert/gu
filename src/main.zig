const std = @import("std");

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const WINDOW_W = 800;
const WINDOW_H = 600;

const FONT = @embedFile("ascii-font");

pub fn main() !void {
    errdefer |err| SDLTryErrorPrint(@errorName(err));

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

    // IMGUI RELATED SETUP

    const num_texture: *c.SDL_Texture = load_num_texture: {
        const stream: *c.SDL_IOStream = try SDLE(c.SDL_IOFromConstMem(FONT, FONT.len));
        const surface: *c.SDL_Surface = try SDLE(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);
        const texture: *c.SDL_Texture = try SDLE(c.SDL_CreateTextureFromSurface(renderer, surface));
        errdefer comptime unreachable;
        break :load_num_texture texture;
    };
    defer c.SDL_DestroyTexture(num_texture);

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

        try DrawRect(renderer, &.{ .x = 0, .y = 0, .w = 400, .h = 600 }, 0x000055FF, 0x2222AAFF);
        try DrawRect(renderer, &.{ .x = 400, .y = 0, .w = 400, .h = 600 }, 0x000055FF, null);

        //try SDLE(c.SDL_SetTextureColorMod(num_texture, 0xC0, 0x00, 0x00));
        try DrawString(renderer, num_texture, 10, 10, "testing... !!@$(#!QOIEANSHT)");

        if (try b1.DrawButton(renderer, &mouse)) {
            std.log.debug("button1 activated!!", .{});
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

fn DrawString(renderer: ?*c.SDL_Renderer, texture: *c.SDL_Texture, x: f32, y: f32, str: []const u8) !void {
    std.debug.assert(std.mem.min(u8, str) >= ' ');
    std.debug.assert(std.mem.max(u8, str) < 127);
    var rolling_x = x;
    var rolling_y = y;
    for (str) |char|
        try DrawChar(renderer, texture, &rolling_x, &rolling_y, char);
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

fn DrawRect(renderer: ?*c.SDL_Renderer, rect: *const c.SDL_FRect, color: u32, outline_color: ?u32) !void {
    try SDLE(c.SDL_SetRenderDrawColor(
        renderer,
        @truncate(color >> 24),
        @truncate(color >> 16),
        @truncate(color >> 8),
        @truncate(color),
    ));
    try SDLE(c.SDL_RenderFillRect(renderer, rect));
    if (outline_color) |col| {
        try SDLE(c.SDL_SetRenderDrawColor(
            renderer,
            @truncate(col >> 24),
            @truncate(col >> 16),
            @truncate(col >> 8),
            @truncate(col),
        ));
        try SDLE(c.SDL_RenderRect(renderer, rect));
    }
}
