const rl = @cImport({
    @cInclude("raylib.h");
});

pub fn main() void {
    rl.InitWindow(500, 500, "My Window");
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(rl.RED);
        rl.EndDrawing();
    }
}
