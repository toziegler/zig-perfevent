const std = @import("std");
const app = @import("app");

const NUM_SAMPLES = 1_000_000;
const MAX_NS = std.time.ns_per_s * 5;

var SAMPLES_BUF: [NUM_SAMPLES]Sample = undefined;
var PERF_FDS = [1]std.os.linux.fd_t{-1} ** PERF_MEASUREMENTS.len;

const PERF_MEASUREMENTS = [_]PerfMeasurement{
    .{
        .name = "cpu_cycles",
        .type = std.os.linux.PERF.TYPE.HARDWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.CPU_CYCLES),
    },
    .{
        .name = "instructions",
        .type = std.os.linux.PERF.TYPE.HARDWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.INSTRUCTIONS),
    },
    .{
        .name = "cache_references",
        .type = std.os.linux.PERF.TYPE.HARDWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.CACHE_REFERENCES),
    },
    .{
        .name = "cache_misses",
        .type = std.os.linux.PERF.TYPE.HARDWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.CACHE_MISSES),
    },
    .{
        .name = "branch_misses",
        .type = std.os.linux.PERF.TYPE.HARDWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.BRANCH_MISSES),
    },
    .{
        .name = "task_clock",
        .type = std.os.linux.PERF.TYPE.SOFTWARE,
        .config = @intFromEnum(std.os.linux.PERF.COUNT.SW.TASK_CLOCK),
    },
};

pub fn name() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const elements_count = 2_000_000; // this is roughly 30TB  in 2MB pages
    const m = try allocator.alloc(u64, elements_count);
    defer allocator.free(m);
    var rand = std.crypto.random;
    var out: u64 = 0;
    for (0..1000000) |_| {
        out = out +% rand.int(u64);
    }
    std.debug.print("out {} \n", .{out});
}

pub fn main() !void {
    const result = bench(name, .{});
    try std.json.stringify(result, std.json.StringifyOptions{}, std.io.getStdOut().writer());
}

const PerfMeasurement = struct {
    name: []const u8,
    type: std.os.linux.PERF.TYPE,
    config: u32,
};

const Sample = struct {
    wall_time: u64,
    utime: u64,
    stime: u64,
    cpu_cycles: u64,
    instructions: u64,
    cache_references: u64,
    cache_misses: u64,
    branch_misses: u64,
    CPUs: f64,
    maxrss: usize,

    fn order(_: void, a: Sample, b: Sample) bool {
        return a.wall_time < b.wall_time;
    }
};

fn timevalToNs(tv: std.os.linux.timeval) u64 {
    const ns_per_us = std.time.ns_per_s / std.time.us_per_s;
    return @as(usize, @bitCast(tv.tv_sec)) * std.time.ns_per_s + @as(usize, @bitCast(tv.tv_usec)) * ns_per_us;
}

fn readPerfFd(fd: std.posix.fd_t) usize {
    var result: usize = 0;
    const n = std.posix.read(fd, std.mem.asBytes(&result)) catch |err| {
        std.debug.panic("unable to read perf fd: {s}\n", .{@errorName(err)});
    };
    std.debug.assert(n == @sizeOf(usize));
    return result;
}

pub fn bench(comptime func: anytype, args: anytype) Sample {
    var rusage: std.os.linux.rusage = undefined;
    const rusage_who: i32 = std.os.linux.rusage.SELF;
    var timer = std.time.Timer.start() catch @panic("need timer to work");
    for (PERF_MEASUREMENTS, 0..) |measurement, i| {
        var attr: std.os.linux.perf_event_attr = .{
            .type = measurement.type,
            .config = measurement.config,
            .flags = .{
                .disabled = true,
                .inherit = true,
                .inherit_stat = false,
                .exclude_kernel = false,
                .exclude_hv = false,
                .exclude_user = false,
            },
        };

        const fd = std.posix.perf_event_open(&attr, 0, -1, PERF_FDS[0], std.os.linux.PERF.FLAG.FD_CLOEXEC) catch |err| {
            std.debug.panic("unable to open perf event: {s}\n", .{@errorName(err)});
        };
        PERF_FDS[i] = fd;
    }
    _ = std.os.linux.getrusage(rusage_who, &rusage);

    for (PERF_MEASUREMENTS, 0..) |_, i| {
        _ = std.os.linux.ioctl(PERF_FDS[i], std.os.linux.PERF.EVENT_IOC.RESET, 0);
        _ = std.os.linux.ioctl(PERF_FDS[i], std.os.linux.PERF.EVENT_IOC.ENABLE, 0);
    }
    const start = timer.read();

    const result = @call(.auto, func, args);

    // split here
    for (PERF_MEASUREMENTS, 0..) |_, i| {
        _ = std.os.linux.ioctl(PERF_FDS[i], std.os.linux.PERF.EVENT_IOC.DISABLE, 0);
    }
    const end = timer.read();
    var end_rusage: std.os.linux.rusage = undefined;
    _ = std.os.linux.getrusage(rusage_who, &end_rusage);
    result catch {
        @panic("benchmark function failed");
    };
    var final_rusage: std.os.linux.rusage = undefined;
    _ = std.os.linux.getrusage(rusage_who, &final_rusage);
    const sample = .{
        .wall_time = end - start,
        .utime = timevalToNs(end_rusage.utime) - timevalToNs(rusage.utime),
        .stime = timevalToNs(end_rusage.stime) - timevalToNs(rusage.stime),
        .cpu_cycles = readPerfFd(PERF_FDS[0]),
        .instructions = readPerfFd(PERF_FDS[1]),
        .cache_references = readPerfFd(PERF_FDS[2]),
        .cache_misses = readPerfFd(PERF_FDS[3]),
        .branch_misses = readPerfFd(PERF_FDS[4]),
        .CPUs = (@as(f64, @floatFromInt(readPerfFd(PERF_FDS[5]))) / (@as(f64, @floatFromInt(timevalToNs(end_rusage.utime) - timevalToNs(rusage.utime))))),
        .maxrss = (@as(usize, @bitCast(final_rusage.maxrss)) / 1024),
    };
    for (&PERF_FDS) |*perf_fd| {
        std.posix.close(perf_fd.*);
        perf_fd.* = -1;
    }
    return sample;
}
