const std = @import("std");
const perfevent = @import("perfevent");

pub fn name(number_hashes: usize) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const elements_count = 2_000_000;
    const m = try allocator.alloc(u64, elements_count);
    defer allocator.free(m);
    var rand = std.crypto.random;
    var out: u64 = 0;
    for (0..number_hashes) |_| {
        out = out +% rand.int(u64);
    }
    std.mem.doNotOptimizeAway(out);
}

const BenchmarkParams = struct {
    name: []const u8 = "demo_benchmark",
    number_hashes: u64,
};
pub fn main() !void {
    var print_header: bool = true;
    inline for (.{ 1_000_000, 2_000_000, 3_000_000, 4_000_000, 5_000_000 }) |number_hashes| {
        var benchmark_params = BenchmarkParams{
            .number_hashes = number_hashes,
        };
        var perf = perfevent.PerfEventBlockType(BenchmarkParams).init(&benchmark_params, print_header);
        defer perf.deinit();
        // update the scale
        perf.set_scale(number_hashes);

        // print_header only once
        print_header = false;

        // benchmark function
        try name(number_hashes);
    }
}
