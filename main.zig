const std = @import("std");

fn get_time() f64 {
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &tp);
    return @as(f64, @floatFromInt(tp.sec)) +
        @as(f64, @floatFromInt(tp.nsec)) /
            @as(f64, 1e9);
}

var start_time: f64 = undefined;

inline fn debug(what: []const u8, args: anytype) void {
    std.debug.print("debug: [{d:.6}s] ", .{get_time() - start_time});
    std.debug.print(what, args);
}

inline fn info(what: []const u8, args: anytype) void {
    std.debug.print("info: ", .{});
    std.debug.print(what, args);
}

const rl = @cImport({
    @cInclude("raylib.h");
});

const C: struct {
    background: rl.Color = .{ .a = 0xFF, .r = 0x1d, .g = 0x20, .b = 0x21 },
    foreground: rl.Color = .{ .a = 0xFF, .r = 0xd4, .g = 0xbe, .b = 0x98 },
    black: rl.Color = .{ .a = 0xFF, .r = 0x92, .g = 0x83, .b = 0x74 },
    red: rl.Color = .{ .a = 0xFF, .r = 0xea, .g = 0x69, .b = 0x62 },
    green: rl.Color = .{ .a = 0xFF, .r = 0xa9, .g = 0xb6, .b = 0x65 },
    yellow: rl.Color = .{ .a = 0xFF, .r = 0xe7, .g = 0x8a, .b = 0x4e },
    blue: rl.Color = .{ .a = 0xFF, .r = 0x7d, .g = 0xae, .b = 0xa3 },
    magenta: rl.Color = .{ .a = 0xFF, .r = 0xd3, .g = 0x86, .b = 0x9b },
    cyan: rl.Color = .{ .a = 0xFF, .r = 0x89, .g = 0xb4, .b = 0x82 },
    white: rl.Color = .{ .a = 0xFF, .r = 0xdd, .g = 0xc7, .b = 0xa1 },
} = .{};

// autocalculated things
const Ctx = struct {
    font: rl.Font = .{},
    font_spacing: f32 = 0,
    font_size: f32 = 36, // default font size
    font_path: [*c]const u8 = "/usr/share/fonts/TTF/IosevkaNerdFontMono-Regular.ttf", // default font path
    prompt: [*c]const u8 = "search: ", // default prompt
    prompt_color: rl.Color = C.foreground,
    text_color: rl.Color = C.foreground,
    bg_color: rl.Color = C.background,
    selected_text_color: rl.Color = C.magenta,
    font_h: f32 = 0,
    font_w: f32 = 0,
    rows: usize = 0,
    cols: usize = 0,
    screen_w: i32 = 600, // default width
    screen_h: i32 = 400, // default height
    entry_list: List = .{},
    input: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,
    margin_l: f32 = 50,
    margin: f32 = 50,
    selected: i32 = 0,
    selected_entry: Entry = .{},
    io: std.Io,
    ignorecase: bool = true,
};

var ctx: Ctx = undefined;

const Entry = struct {
    efec_name: ?[]const u8 = null,
    real_name: ?[:0]const u8 = null,
    exec: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    terminal: ?[]const u8 = null,
    gap: i32 = 0,

    pub fn match(e: *Entry, text: []const u8) bool {
        var i: usize = 0;
        var gap: i32 = 0;
        if (e.efec_name.?.len < text.len) return false;
        for (text) |ch| {
            for (i..e.efec_name.?.len) |j| {
                if (e.efec_name.?[j] == ch or ctx.ignorecase and
                    0 < ch and ch < 128 and
                    0 < e.efec_name.?[j] and e.efec_name.?[j] < 128 and
                    std.ascii.toLower(ch) == std.ascii.toLower(e.efec_name.?[j]))
                {
                    i = j + 1;
                    if (gap <= 0) {
                        gap -= 1;
                    } else {
                        gap = 0;
                    }
                    e.gap += gap;
                    break;
                }
                gap += 2;
            } else {
                return false;
            }
        }
        return true;
    }

    pub fn dup(e: Entry) !Entry {
        var e2: Entry = e;
        if (e.efec_name) |v| e2.efec_name = try ctx.allocator.dupe(u8, v);
        if (e.real_name) |v| e2.real_name = try ctx.allocator.dupeZ(u8, v);
        if (e.exec) |v| e2.exec = try ctx.allocator.dupe(u8, v);
        if (e.icon) |v| e2.icon = try ctx.allocator.dupe(u8, v);
        if (e.terminal) |v| e2.terminal = try ctx.allocator.dupe(u8, v);
        return e2;
    }

    pub fn destroy(e: Entry) void {
        if (e.efec_name) |v| ctx.allocator.free(v);
        if (e.real_name) |v| ctx.allocator.free(v);
        if (e.exec) |v| ctx.allocator.free(v);
        if (e.icon) |v| ctx.allocator.free(v);
        if (e.terminal) |v| ctx.allocator.free(v);
    }
};

fn entry_less_than(_: void, e1: Entry, e2: Entry) bool {
    return e1.gap < e2.gap;
}

inline fn extractValue(content: []const u8, comptime prefix: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, content, prefix)) {
        if (content.len > prefix.len) {
            return std.mem.trim(u8, content[prefix.len..], &std.ascii.whitespace);
        }
    }
    return null;
}

fn parse_entry(entry: std.Io.Dir.Entry, file: std.Io.File) !?Entry {
    var buf: [4096]u8 = undefined;
    var r = file.reader(ctx.io, &buf);
    var values: Entry = .{};

    while (try r.interface.takeDelimiter('\n')) |line| {
        const content = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (extractValue(content, "Name=")) |value| {
            if (values.efec_name) |_| continue;
            values.efec_name = try ctx.allocator.dupe(u8, value);
            values.real_name = try ctx.allocator.dupeZ(u8, value);
            continue;
        }

        if (extractValue(content, "Exec=")) |value| {
            if (values.exec) |_| continue;
            values.exec = try ctx.allocator.dupe(u8, value);
            continue;
        }

        if (extractValue(content, "Icon=")) |value| {
            if (values.icon) |_| continue;
            values.icon = try ctx.allocator.dupe(u8, value);
            continue;
        }

        if (extractValue(content, "Terminal=")) |value| {
            if (values.terminal) |_| continue;
            values.terminal = try ctx.allocator.dupe(u8, value);
            continue;
        }

        if (extractValue(content, "NoDisplay=")) |value| {
            if (std.mem.eql(u8, value, "true")) {
                values.destroy();
                return null;
            }
            if (std.mem.eql(u8, value, "false")) {} else {
                return error.ValueIsNeitherTrueNorFalse;
            }
            continue;
        }
    }

    if (values.efec_name) |_| {
        return values;
    } else {
        info("Entry {s} has no name\n", .{entry.name});
        values.destroy();
        return null;
    }
}

const List = struct {
    list: std.ArrayList(Entry) = .empty,

    pub fn get(l: List, i: usize) Entry {
        std.debug.assert(l.list.items.len > i);
        return l.list.items[i];
    }

    pub fn append(l: *List, e: Entry) !void {
        try l.list.append(ctx.allocator, e);
    }

    pub fn destroy(l: *List) void {
        for (l.list.items) |e| {
            e.destroy();
        }
        l.list.deinit(ctx.allocator);
    }

    pub fn filter(l: List, text: []const u8) !List {
        var lnew: List = .{};
        for (0..l.list.items.len) |i| {
            var e: Entry = l.get(i);
            if (e.match(text)) {
                try lnew.append(try e.dup());
            }
        }
        std.mem.sort(Entry, lnew.list.items, {}, comptime entry_less_than);
        return lnew;
    }
};

fn parse_desktop_dir(l: *List, path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    var dir = try cwd.openDir(ctx.io, path, .{ .iterate = true });
    defer dir.close(ctx.io);

    var iter = dir.iterateAssumeFirstIteration();

    while (try iter.next(ctx.io)) |entry| {
        const file = try dir.openFile(ctx.io, entry.name, .{});
        defer file.close(ctx.io);
        if (try parse_entry(entry, file)) |e| {
            try l.append(e);
        }
    }
}

fn update_screen() !void {
    var position: rl.Vector2 = .{ .x = ctx.margin, .y = ctx.margin };

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

    var filtered = try ctx.entry_list.filter(i_slice);
    defer filtered.destroy();

    if (filtered.list.items.len <= 0) return;

    // sanity oob check
    if (ctx.selected >= filtered.list.items.len) ctx.selected = 0;
    if (ctx.selected < 0) ctx.selected = @intCast(filtered.list.items.len - 1);

    ctx.selected_entry.destroy();
    ctx.selected_entry = try filtered.get(@intCast(ctx.selected)).dup();

    const window_size: i32 = @intCast(ctx.rows - 1);
    const window_n: i32 = @divTrunc(ctx.selected, window_size);

    position.x = ctx.margin + ctx.margin_l;
    for (0.., filtered.list.items) |i, e| {
        // todo: improve this, there are a lot of wasted iterations
        if (i < window_n * window_size) continue;
        if (i >= (window_n + 1) * window_size) continue;
        position.y += ctx.font_h;

        if (i == ctx.selected) {
            rl.DrawTextEx(ctx.font, e.real_name.?, position, ctx.font_size, 0, ctx.selected_text_color);
        } else {
            rl.DrawTextEx(ctx.font, e.real_name.?, position, ctx.font_size, 0, ctx.text_color);
        }
    }
}

fn _init(init: std.process.Init) !void {
    debug("start init\n", .{});
    ctx = .{
        .allocator = init.gpa,
        .io = init.io,
    };

    debug("start raylib init\n", .{});
    debug("start set trace log level\n", .{});
    rl.SetTraceLogLevel(rl.LOG_ERROR);
    debug("end set trace log level\n", .{});
    debug("start rl init window\n", .{});
    rl.InitWindow(ctx.screen_w, ctx.screen_h, "zrun");
    debug("end rl init window\n", .{});

    debug("start rl load font\n", .{});
    ctx.font = rl.LoadFontEx(ctx.font_path, @intFromFloat(ctx.font_size), null, 0);
    if (!rl.IsFontValid(ctx.font)) {
        info("Font {s} is not valid\n", .{ctx.font_path});
        rl.CloseWindow();
        return;
    }
    debug("end rl load font\n", .{});
    debug("end raylib init\n", .{});

    update_globals();

    debug("start parse_desktop_dir\n", .{});
    parse_desktop_dir(&ctx.entry_list, "/usr/share/applications/") catch {};
    parse_desktop_dir(&ctx.entry_list, "/home/hugo/.local/share/applications/") catch {};
    debug("end parse_desktop_dir\n", .{});

    const entries = ctx.entry_list.list.items.len;
    if (entries <= 0) {
        info("No .desktop files\n", .{});
        rl.CloseWindow();
        return;
    } else {
        info("Found {} .desktop files\n", .{entries});
    }
    debug("end init\n", .{});
}

fn _fini() !void {
    ctx.entry_list.destroy();
    ctx.selected_entry.destroy();
    ctx.input.deinit(ctx.allocator);
}

fn update_globals() void {
    ctx.screen_w = rl.GetScreenWidth();
    ctx.screen_h = rl.GetScreenHeight();

    std.debug.assert(ctx.font_size == @as(f32, @floatFromInt(ctx.font.baseSize)));
    ctx.font_w = (ctx.font.recs[0].width + ctx.font_spacing);
    ctx.font_h = (ctx.font.recs[0].height + ctx.font_spacing);

    std.debug.assert(ctx.font_w > 0);
    std.debug.assert(ctx.font_h > 0);

    ctx.rows = @intFromFloat((@as(f32, @floatFromInt(ctx.screen_h)) - 2 * ctx.margin) / ctx.font_h);
    ctx.cols = @intFromFloat((@as(f32, @floatFromInt(ctx.screen_w)) - 2 * ctx.margin) / ctx.font_w);

    info("New size: {}, {}\n", .{ ctx.screen_h, ctx.screen_w });
    info("Cols: {} Rows: {}\n", .{ ctx.cols, ctx.rows });
}

fn select_and_run() !void {
    const e: Entry = ctx.selected_entry;
    info("Selected: {s}\n", .{e.efec_name.?});
    info("     run: {s}\n", .{e.exec.?});

    _ = try std.process.spawn(ctx.io, .{
        .argv = &.{ "sh", "-c", e.exec.? },
    });

    return error.NoError;
}

fn capture_input() !void {
    while (true) {
        const k = rl.GetKeyPressed();
        if (k == 0) break;

        if (k == rl.KEY_BACKSPACE) {
            _ = ctx.input.pop();
        }

        if (k == rl.KEY_ENTER) {
            try select_and_run();
            ctx.input.clearRetainingCapacity();
        }

        if ((rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL)) and k == rl.KEY_J or k == rl.KEY_DOWN) {
            ctx.selected += 1;
            continue;
        }

        if ((rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL)) and k == rl.KEY_K or k == rl.KEY_UP) {
            ctx.selected -= 1;
            continue;
        }

        if (0 < k and k < 128 and std.ascii.isAlphanumeric(@intCast(k))) {
            info("key {} pressed\n", .{k});
            if (!ctx.ignorecase and (rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT))) {
                try ctx.input.append(ctx.allocator, std.ascii.toUpper(@intCast(k)));
            } else {
                try ctx.input.append(ctx.allocator, std.ascii.toLower(@intCast(k)));
            }
        } else {
            info("Non printable key {} pressed\n", .{k});
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
            rl.ClearBackground(ctx.bg_color);
            try capture_input();
            try update_screen();
        } else {
            rl.ClearBackground(rl.RED);
        }
        rl.EndDrawing();
    }
}

pub fn main(init: std.process.Init) !void {
    start_time = get_time();
    _init(init) catch {
        try _fini();
        return;
    };
    loop() catch {
        try _fini();
        return;
    };
    try _fini();
}
