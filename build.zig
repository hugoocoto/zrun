const std = @import("std");  
  
pub fn build(b: *std.Build) void {  
    const exe = b.addExecutable(.{  
        .name = "my_program",  
        .root_module = b.createModule(.{  
            .root_source_file = b.path("main.zig"),  
            .target = b.graph.host,  
            .optimize = .Debug,  
        }),  
    });  
  
    // Add the directory containing your .a and .so files  
    exe.root_module.addLibraryPath(b.path("./raylib-6.0_linux_amd64/lib/"));  
      
    // Add runtime library path for .so files  
    exe.root_module.addRPath(b.path("./raylib-6.0_linux_amd64/lib/"));  
  
    // Link against your library (without 'lib' prefix and extension)  
    exe.root_module.linkSystemLibrary("libraylib", .{  
        .needed = true,  
    });  
  
    // If your library depends on libc  
    exe.root_module.link_libc = true;  
}
