const std = @import("std");
const perfevent = @import("perfevent");

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
    var perf = perfevent.PerfEventBlock.init(1000000, true);
    defer perf.deinit();
    try name();
}
