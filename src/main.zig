const std = @import("std");

const c = @import("c.zig").c;
const SDLE = @import("c.zig").SDLE;
const SDLTryErrorPrint = @import("c.zig").SDLTryErrorPrint;

const WINDOW_W = 800;
const WINDOW_H = 600;

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
        try SDLE(c.SDL_CreateWindowAndRenderer("CHIP-8", WINDOW_W, WINDOW_H, 0, &w, &r));
        errdefer comptime unreachable;
        break :create_window_and_renderer .{ w, r };
    };
    defer c.SDL_DestroyRenderer(renderer);
    defer c.SDL_DestroyWindow(window);

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
                else => {},
            }
        }

        try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x22, 0xFF));
        try SDLE(c.SDL_RenderClear(renderer));

        //const rect = c.SDL_FRect{ .x = 10, .y = 10, .w = 256, .h = 128 };
        //try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x55, 0xFF));
        //try SDLE(c.SDL_RenderFillRect(renderer, &rect));
        //try SDLE(c.SDL_SetRenderDrawColor(renderer, 0x22, 0x22, 0xFF, 0xFF));
        //try SDLE(c.SDL_RenderRect(renderer, &rect));

        try SDLE(c.SDL_RenderPresent(renderer));
    }
}
