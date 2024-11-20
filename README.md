# PerfEvent
A thin zig wrapper for Linux' perf event API.
Inspired by https://github.com/viktorleis/perfevent

## Import
1) Run the following command:
`zig fetch --save https://github.com/toziegler/zig-perfevent/archive/refs/heads/main.tar.gz`
or add the following snippet to `build.zig.zon`:
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
## Usage
```zig
pub fn main() !void {
   const scale: u64 = 10000;
    {
       var perf = perfevent.PerfEventBlock.init(scale, true);
       defer perf.deinit();
       for (0..scale) |_| {
          try do_operation();
       }
    }
}

```

This prints something like this:
```csv
wall_time,utime,stime,cpu_cycles,instructions,cache_references,cache_misses,branch_misses,CPUs,GHZ,maxrss_mb,scale
82405439,82361000,0,305.68,732.06,1.67,0.43,0.27,1.00,3.71,16,1000000
```

## Troubleshooting

You may need to run sudo sysctl -w kernel.perf_event_paranoid=-1 and/or add kernel.perf_event_paranoid = -1 to /etc/sysctl.conf
