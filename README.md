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

const BenchmarkParams = struct {
    name: []const u8 = "demo_benchmark",
    number_hashes: u64,
};

pub fn main() !void {
   const scale: u64 = 10000;
    {
       var benchmark_params = BenchmarkParams{
           .number_hashes = number_hashes,
       };
       var perf = perfevent.PerfEventBlockType(BenchmarkParams).init(&benchmark_params, print_header);
       perf.set_scale(scale);
       defer perf.deinit();
       for (0..scale) |_| {
          try do_operation();
       }
    }
}

```

This prints something like this if piped in `column -s, -t` otherwise a simple csv is generated:
```csv
name            number_hashes  wall_time  utime      stime    cpu_cycles  k_cycles  instructions  cache_references  cache_misses  branch_misses  GHZ   CPUs  maxrss_mb  scale
demo_benchmark  1000000        168087221  167919000  0        621.79      9.37      731.97        2.13              0.09          0.49           3.70  1.00  16         1000000
demo_benchmark  2000000        331796576  328056000  3333000  613.76      5.01      729.93        1.08              0.05          0.46           3.70  1.01  16         2000000
demo_benchmark  3000000        497649857  492656000  2372000  613.69      6.33      729.72        0.85              0.04          0.45           3.70  1.01  16         3000000
demo_benchmark  4000000        659257685  655107000  3323000  609.76      2.91      728.92        0.60              0.03          0.43           3.70  1.01  16         4000000
demo_benchmark  5000000        817775392  813461000  3330000  605.06      2.45      728.72        0.49              0.03          0.44           3.70  1.01  16         5000000
```

## Troubleshooting

You may need to run sudo sysctl -w kernel.perf_event_paranoid=-1 and/or add kernel.perf_event_paranoid = -1 to /etc/sysctl.conf
