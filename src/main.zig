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
    //const num_w: f32 = 10;
    //const num_h: f32 = 20;

    var mouse_x: f32 = -100;
    var mouse_y: f32 = -100;

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
                    mouse_x = event.motion.x;
                    mouse_y = event.motion.y;
                },
                else => {},
            }
        }

        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x22, 0xFF));
        try SDLE(c.SDL_RenderClear(renderer));

        const rect1 = c.SDL_FRect{ .x = 0, .y = 0, .w = 400, .h = 600 };
        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x55, 0xFF));
        try SDLE(c.SDL_RenderFillRect(renderer, &rect1));
        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x22, 0x22, 0xFF, 0xFF));
        try SDLE(c.SDL_RenderRect(renderer, &rect1));

        const rect2 = c.SDL_FRect{ .x = 400, .y = 0, .w = 400, .h = 600 };
        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x55, 0xFF));
        try SDLE(c.SDL_RenderFillRect(renderer, &rect2));
        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x22, 0x22, 0xAA, 0xFF));
        try SDLE(c.SDL_RenderRect(renderer, &rect2));

        //try SDLE(c.SDL_SetTextureColorMod(num_texture, 0xC0, 0x00, 0x00));
        try DrawString(renderer, num_texture, 10, 10, "testing... !!@$(#!QOIEANSHT)");

        const rect_mouse = c.SDL_FRect{ .x = mouse_x - 4, .y = mouse_y - 4, .w = 8, .h = 8 };
        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0xFF, 0x00, 0xFF));
        try SDLE(c.SDL_RenderFillRect(renderer, &rect_mouse));

        try SDLE(c.SDL_RenderPresent(renderer));
    }
}

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
