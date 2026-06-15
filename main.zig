const rl = @cImport({
    @cInclude("./raylib-6.0_linux_amd64/include/raylib.h");
});

pub fn main() void {
    rl.InitWindow(500, 500, "My Window");
    while (!rl.ShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(rl.RED);
        rl.EndDrawing();
    }
}
