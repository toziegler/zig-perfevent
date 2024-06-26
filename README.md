`build.zig.zon`
```zig
    .dependencies = .{
        .perfevent = .{
            .url = "https://github.com/toziegler/zig-perfevent/archive/master.tar.gz",
            .hash = "1220a0b41b944a024d50316d7e7b5ac9496b4c68d0aa93c6d3da18309a2130d9b25e",
        },
    },
```

`build.zig` 
```zig
    const perfevent = b.dependency("perfevent", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("perfevent", perfevent.module("perfevent"));
```
