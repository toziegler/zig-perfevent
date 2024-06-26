const std = @import("std");

const PerfMeasurement = struct {
    name: []const u8,
    type: std.os.linux.PERF.TYPE,
    config: u32,
};

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

pub const PerfEventBlock = struct {
    const Event = struct {
        const ReadFormat = extern struct {
            value: u64 = 0,
            time_enabled: u64 = 0,
            time_running: u64 = 0,
        };
        fd: std.posix.fd_t = -1,
        prev: ReadFormat = .{},
        current: ReadFormat = .{},
    };

    //perf_fds: [PERF_MEASUREMENTS.len]std.posix.fd_t = [_]std.os.linux.fd_t{-1} ** PERF_MEASUREMENTS.len,
    perf_events: [PERF_MEASUREMENTS.len]Event = [_]Event{.{}} ** PERF_MEASUREMENTS.len,
    begin_time: u64,
    timer: std.time.Timer,
    begin_rusage: std.posix.system.rusage,
    print_header: bool,
    scale: u64,

    const Sample = struct {
        wall_time: u64,
        utime: u64,
        stime: u64,
        cpu_cycles: f64,
        instructions: f64,
        cache_references: f64,
        cache_misses: f64,
        branch_misses: f64,
        GHZ: f64,
        CPUs: f64,
        maxrss_mb: usize,
        scale: u64,
    };

    fn timevalToNs(tv: std.posix.timeval) u64 {
        const ns_per_us = std.time.ns_per_s / std.time.us_per_s;
        return @as(usize, @bitCast(tv.tv_sec)) * std.time.ns_per_s + @as(usize, @bitCast(tv.tv_usec)) * ns_per_us;
    }

    fn readPerfFd(fd: std.posix.fd_t, read_format: *Event.ReadFormat) void {
        var read: usize = 0;
        var buffer = std.mem.asBytes(read_format);
        while (read < @sizeOf(Event.ReadFormat)) {
            const n = std.posix.read(fd, buffer[read..24]) catch |err| {
                std.debug.panic("unable to read perf fd: {s}\n", .{@errorName(err)});
            };
            read += n;
        }
        std.debug.assert(read == @sizeOf(Event.ReadFormat));
    }

    fn readCounter(event: *Event) f64 {
        const multiplexing_correction = ((@as(f64, @floatFromInt(event.current.time_enabled))) - (@as(f64, @floatFromInt(event.prev.time_enabled)))) / ((@as(f64, @floatFromInt(event.current.time_running))) - (@as(f64, @floatFromInt(event.prev.time_running))));
        return (@as(f64, @floatFromInt(event.current.value - event.prev.value))) * multiplexing_correction;
    }

    pub fn init(scale: u64, print_header: bool) PerfEventBlock {
        var perf_events: [PERF_MEASUREMENTS.len]Event = [_]Event{.{}} ** PERF_MEASUREMENTS.len;
        //var perf_events = [_]u64{0} ** PERF_MEASUREMENTS.len;
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
                .read_format = 1 & 2,
            };

            const fd = std.posix.perf_event_open(&attr, 0, -1, -1, std.os.linux.PERF.FLAG.FD_CLOEXEC) catch |err| {
                std.debug.panic("unable to open perf event: {s}\n", .{@errorName(err)});
            };
            perf_events[i].fd = fd;
        }
        const begin_rusage = std.posix.getrusage(std.posix.rusage.SELF);

        for (PERF_MEASUREMENTS, 0..) |_, i| {
            _ = std.os.linux.ioctl(perf_events[i].fd, std.os.linux.PERF.EVENT_IOC.RESET, 0);
            _ = std.os.linux.ioctl(perf_events[i].fd, std.os.linux.PERF.EVENT_IOC.ENABLE, 0);
            readPerfFd(perf_events[i].fd, &perf_events[i].prev);
        }
        const start = timer.read();
        return .{
            .begin_time = start,
            .perf_events = perf_events,
            .timer = timer,
            .begin_rusage = begin_rusage,
            .print_header = print_header,
            .scale = scale,
        };
    }

    pub fn deinit(self: *PerfEventBlock) void {
        for (&self.perf_events) |*event| {
            readPerfFd(event.fd, &event.current);
        }

        const end_time = self.timer.read();
        const end_rusage = std.posix.getrusage(std.posix.rusage.SELF);
        const scale_f = @as(f64, @floatFromInt(self.scale));
        const cycles = readCounter(&self.perf_events[0]);
        const task_clock = readCounter(&self.perf_events[5]);
        const sample = .{
            .wall_time = end_time - self.begin_time,
            .utime = timevalToNs(end_rusage.utime) - timevalToNs(self.begin_rusage.utime),
            .stime = timevalToNs(end_rusage.stime) - timevalToNs(self.begin_rusage.stime),
            .cpu_cycles = (cycles / scale_f),
            .instructions = (readCounter(&self.perf_events[1]) / scale_f),
            .cache_references = (readCounter(&self.perf_events[2]) / scale_f),
            .cache_misses = (readCounter(&self.perf_events[3]) / scale_f),
            .branch_misses = (readCounter(&self.perf_events[4]) / scale_f),
            .CPUs = task_clock / (@as(f64, @floatFromInt(timevalToNs(end_rusage.utime) - timevalToNs(self.begin_rusage.utime)))),
            .GHZ = cycles / task_clock,
            .maxrss_mb = (@as(usize, @bitCast(end_rusage.maxrss)) / 1024),
            .scale = self.scale,
        };
        for (&self.perf_events) |*event| {
            std.posix.close(event.fd);
            event.fd = -1;
        }
        // normalization and print
        const writer = std.io.getStdOut().writer();
        if (self.print_header) {
            inline for (std.meta.fields(@TypeOf(sample)), 0..) |f, i| {
                if (i > 0) writer.print(",", .{}) catch {};
                writer.print("{s}", .{f.name}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }
        // body
        {
            inline for (std.meta.fields(@TypeOf(sample)), 0..) |f, i| {
                if (i > 0) writer.print(",", .{}) catch {};
                writer.print("{d:.2}", .{@field(sample, f.name)}) catch {
                    std.log.debug("", .{});
                };
            }
            writer.print("\n", .{}) catch {};
        }
    }
};
