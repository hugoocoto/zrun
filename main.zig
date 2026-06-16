const std = @import("std");
const print = std.debug.print;

const rl = @cImport({
    @cInclude("raylib.h");
});

// autocalculated things
const Ctx = struct {
    font: rl.Font = .{},
    font_spacing: f32 = 0,
    font_size: f32 = 40, // default font size
    font_path: [*c]const u8 = "/usr/share/fonts/TTF/IosevkaNerdFontMono-Medium.ttf", // default font path
    prompt: [*c]const u8 = "search:", // default prompt
    prompt_color: rl.Color = .{ .a = 0xFF, .r = 0xFF, .g = 0xFF, .b = 0xFF },
    text_color: rl.Color = .{ .a = 0xFF, .r = 0xFF, .g = 0xFF, .b = 0xFF },
    bg_color: rl.Color = .{ .a = 0xFF, .r = 0xFF, .g = 0xFF, .b = 0xFF },
    font_h: f32 = 0,
    font_w: f32 = 0,
    rows: usize = 0,
    cols: usize = 0,
    screen_w: i32 = 400, // default width
    screen_h: i32 = 600, // default height
    entry_list: List = .{},
    input: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,
    margin_l: f32 = 50,
    selected: i32 = 0,
};

var ctx: Ctx = undefined;

const Entry = struct {
    text: []const u8,

    pub fn match(e: Entry, text: []const u8) bool {
        return std.mem.startsWith(u8, e.text, text);
    }
};

const List = struct {
    list: std.ArrayList(Entry) = .empty,

    pub fn get(l: List, i: usize) Entry {
        std.debug.assert(l.list.items.len > i);
        return l.list.items[i];
    }

    pub fn append(l: *List, e: Entry) void {
        l.list.append(ctx.allocator, e) catch |err| {
            print("Error {}\n", .{err});
        };
    }

    pub fn destroy(l: *List) void {
        for (l.list.items) |e| {
            ctx.allocator.free(e.text);
        }
        l.list.deinit(ctx.allocator);
    }

    pub fn filter(l: List, text: []const u8) !List {
        var lnew: List = .{};
        for (0..l.list.items.len) |i| {
            var e: Entry = l.get(i);
            if (e.match(text)) {
                e.text = try ctx.allocator.dupe(u8, e.text);
                lnew.append(e);
            }
        }
        return lnew;
    }
};

fn parse_desktop_dir(init: std.process.Init, l: *List, path: []const u8) !void {
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    var dir = try cwd.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterateAssumeFirstIteration();

    while (try iter.next(io)) |entry| {
        std.debug.print("file: {s}\n", .{entry.name});
        l.append(.{ .text = try ctx.allocator.dupe(u8, entry.name) });
    }
}

fn update_screen() !void {
    var position: rl.Vector2 = .{ .x = 0, .y = 0 };

    // this chunk is just for concat two cstr
    const p_slice = std.mem.span(ctx.prompt);
    // todo: the following two lines should be moved to something more performant
    const i_slice = try ctx.input.toOwnedSlice(ctx.allocator); // this empty the array
    try ctx.input.appendSlice(ctx.allocator, i_slice); // this refill the array
    defer ctx.allocator.free(i_slice);
    const parts = &[_][]const u8{ p_slice, i_slice };
    const prompt: []const u8 = try std.mem.concat(ctx.allocator, u8, parts);
    const prompt_z: [:0]const u8 = try ctx.allocator.dupeZ(u8, prompt);
    defer ctx.allocator.free(prompt);
    defer ctx.allocator.free(prompt_z);

    rl.DrawTextEx(ctx.font, prompt_z, position, ctx.font_size, 0, ctx.prompt_color);

    const count = ctx.rows - 1;

    var filtered = try ctx.entry_list.filter(i_slice);
    defer filtered.destroy();

    for (0..count) |i| {
        if (i >= filtered.list.items.len) break; // oob check
        const e: Entry = filtered.get(i);
        position.x = ctx.margin_l;
        position.y += ctx.font_h;

        const txt = try ctx.allocator.dupeZ(u8, e.text);
        defer ctx.allocator.free(txt);
        rl.DrawTextEx(ctx.font, txt, position, ctx.font_size, 0, ctx.prompt_color);
    }
}

fn _fini(init: std.process.Init, allocator: std.mem.Allocator) !void {
    _ = init;
    _ = allocator;
    ctx.entry_list.destroy();
    ctx.input.deinit(ctx.allocator);
}

fn _init(init: std.process.Init, allocator: std.mem.Allocator) !void {
    ctx = .{ .allocator = allocator };

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE); // maybe floating
    rl.InitWindow(ctx.screen_w, ctx.screen_h, "zrun");

    ctx.font = rl.LoadFontEx(ctx.font_path, @intFromFloat(ctx.font_size), null, 0);
    if (!rl.IsFontValid(ctx.font)) {
        print("Font {s} is not valid\n", .{ctx.font_path});
        rl.CloseWindow();
        return;
    }

    update_globals();

    parse_desktop_dir(init, &ctx.entry_list, "/home/hugo/.local/share/applications/") catch {};
    parse_desktop_dir(init, &ctx.entry_list, "/usr/share/applications/") catch {};

    const entries = ctx.entry_list.list.items.len;
    if (entries <= 0) {
        print("There is no .desktop files\n", .{});
        rl.CloseWindow();
        return;
    } else {
        print("Found {} .desktop files\n", .{entries});
    }
}

fn update_globals() void {
    ctx.screen_w = rl.GetScreenWidth();
    ctx.screen_h = rl.GetScreenHeight();

    std.debug.assert(ctx.font_size == @as(f32, @floatFromInt(ctx.font.baseSize)));
    ctx.font_w = (ctx.font.recs[0].width + ctx.font_spacing);
    ctx.font_h = (ctx.font.recs[0].height + ctx.font_spacing);

    std.debug.assert(ctx.font_w > 0);
    std.debug.assert(ctx.font_h > 0);

    ctx.rows = @intFromFloat(@as(f32, @floatFromInt(ctx.screen_h)) / ctx.font_h);
    ctx.cols = @intFromFloat(@as(f32, @floatFromInt(ctx.screen_w)) / ctx.font_w);

    print("New size: {}, {}\n", .{ ctx.screen_h, ctx.screen_w });
    print("cols: {} rows: {}\n", .{ ctx.cols, ctx.rows });
}

fn select_and_run() !void {
    print("HAVE TO RUN!\n", .{});
}

fn capture_input() !void {
    if (rl.IsKeyPressed(rl.KEY_BACKSPACE)) {
        _ = ctx.input.pop();
    }
    if (rl.IsKeyPressed(rl.KEY_ENTER)) {
        try select_and_run();
        ctx.input.clearRetainingCapacity();
    }
    for (0..128) |i| {
        if (rl.IsKeyPressed(rl.KEY_BACKSPACE)) continue;
        if (rl.IsKeyPressed(rl.KEY_ENTER)) continue;

        if (rl.IsKeyPressed(@intCast(i))) {
            if (std.ascii.isAlphanumeric(@intCast(i))) {
                print("key {} pressed\n", .{i});
                if (rl.IsKeyDown(rl.KEY_LEFT_SHIFT) and rl.IsKeyDown(rl.KEY_RIGHT_SHIFT)) {
                    try ctx.input.append(ctx.allocator, std.ascii.toUpper(@intCast(i)));
                } else {
                    try ctx.input.append(ctx.allocator, std.ascii.toLower(@intCast(i)));
                }
            } else {
                print("Non printable key {} pressed\n", .{i});
            }
        }
    }
}

fn loop() !void {
    while (!rl.WindowShouldClose()) {
        if (rl.IsWindowResized()) {
            update_globals();
        }
        rl.BeginDrawing();
        if (ctx.cols > 0 and ctx.rows > 0) {
            rl.ClearBackground(rl.BLACK);
            try capture_input();
            try update_screen();
        } else {
            rl.ClearBackground(rl.RED);
        }
        rl.EndDrawing();
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    _init(init, allocator) catch try _fini(init, allocator);
    loop() catch try _fini(init, allocator);
    try _fini(init, allocator);
}
