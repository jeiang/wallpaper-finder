const std = @import("std");
const cli = @import("zig-cli");

const config = @import("config.zig");
const png = @import("png.zig");
const jpg = @import("jpg.zig");

const utils = @import("utils.zig");
const Dimensions = utils.Dimensions;

pub var std_options = .{
    // Define logFn to override the std implementation
    .logFn = @import("log.zig").customLogger,
};

// allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var path_buffer = [_]u8{0} ** std.fs.MAX_PATH_BYTES;

// image parsers
const parsers = .{
    jpg,
    png,
};

// output
const stdout = std.io.getStdOut().writer();

const logger = std.log.scoped(.main);

pub fn main() !void {
    return cli.run(config.CreateApp(run), allocator);
}

fn run() !void {
    const conf = try config.GetConfig();

    for (conf.paths) |path| {
        const root = utils.openDir(path) catch |err| {
            logger.err("got err {!}, skipping path: `{s}`", .{ err, path });
            continue;
        };
        logger.info("opened path at `{s}`", .{path});

        var walker = try root.walk(allocator);
        while (try walker.next()) |entry| {
            logger.info("checking path: `{s}`", .{entry.path});
            if (entry.kind != .file) {
                logger.debug("skipping `{s}` because it is a {any}", .{ entry.path, entry.kind });
                continue;
            }
            var file = root.openFile(entry.path, .{}) catch |err| {
                logger.warn("failed to open `{s}` due to {!}, skipping", .{ entry.path, err });
                continue;
            };
            defer file.close();
            const dim = getDimensions(&file, conf.skip_extension_check, entry.path, entry.basename) orelse continue;

            const f64_dim = Dimensions(f64){
                .height = @floatFromInt(dim.height),
                .width = @floatFromInt(dim.width),
            };
            logger.debug("image dimensions of `{s}` is {any}", .{ entry.path, f64_dim });

            if (checkIfWithinSize(conf.size, f64_dim)) {
                const resolved_path = root.realpath(entry.path, &path_buffer) catch |err| {
                    logger.err("failed to resolve path `{s}` from `{s}` because {!}", .{ entry.path, path, err });
                    continue;
                };
                try stdout.print("{s}\n", .{resolved_path});
            }
        }
    }
}

fn getDimensions(file: *std.fs.File, skip_extension_check: bool, path: []const u8, basename: []const u8) ?Dimensions(u32) {
    if (skip_extension_check) {
        inline for (parsers) |parser| {
            if (!@hasDecl(parser, "extensions") or !@hasDecl(parser, "getSize")) {
                @compileError("parser requires field `extensions` and method getSize");
            }
            const getSize = @field(parser, "getSize");
            const possible_size = getSize(file);
            if (possible_size) |size| {
                return size;
            } else |err| {
                if (err == utils.ImageError.MissingSignature) {
                    logger.info("{s} did not match " ++ @typeName(parser) ++ "'s signature, continuing checks", .{path});
                } else {
                    logger.warn("failed to parse `{s}` as a " ++ @typeName(parser) ++ " due to {!}, skipping despite matching signature", .{ path, err });
                }
            }
        }
    } else {
        const extension_idx = std.mem.indexOfScalar(u8, basename, '.') orelse {
            logger.debug("extension not found on `{s}`, skipping", .{path});
            return null;
        };
        const extension = basename[extension_idx..basename.len];
        const lowercase_extension = allocator.alloc(u8, extension.len) catch |err| {
            logger.err("failed to allocate space for lowercase extension because {!}", .{err});
            return null;
        };
        defer allocator.free(lowercase_extension);
        for (0.., lowercase_extension) |idx, *char| {
            char.* = std.ascii.toLower(extension[idx]);
        }

        inline for (parsers) |parser| {
            if (!@hasDecl(parser, "extensions") or !@hasDecl(parser, "getSize")) {
                @compileError("parser requires field `extensions` and method getSize");
            }
            const getSize = @field(parser, "getSize");
            const known_extensions = @field(parser, "extensions");
            inline for (known_extensions) |known_extension| {
                if (std.mem.eql(u8, known_extension, lowercase_extension)) {
                    return getSize(file) catch |err| {
                        logger.warn("failed to parse `{s}` as a " ++ known_extension ++ " due to {!}, skipping", .{ path, err });
                        return null;
                    };
                }
            }
        }
    }

    logger.debug("`{s}` did not match any files, skipping", .{path});
    return null;
}

fn checkIfWithinSize(bounds: config.ComparisonBounds, dim: Dimensions(f64)) bool {
    var within_size = false;
    switch (bounds) {
        .aspect_ratio => |ratio| {
            const dim_ratio = dim.width / dim.height;
            logger.debug("matching on aspect ratio with ratio {e}", .{dim_ratio});
            switch (ratio) {
                .above => |lower| {
                    logger.debug("matching images horizontally wider than ratio {e}", .{lower});
                    within_size = dim_ratio >= lower;
                },
                .below => |upper| {
                    logger.debug("matching images horizontally slimmer than ratio {e}", .{upper});
                    within_size = dim_ratio <= upper;
                },
                .between => |between| {
                    logger.debug("matching images with a ratio between {e} and {e}", .{ between.lower, between.upper });
                    within_size = between.lower <= dim_ratio and dim_ratio <= between.upper;
                },
            }
        },
        .resolution => |resolution| switch (resolution) {
            .above => |lower| {
                logger.debug("checking if image dimension {any} is greater than wanted dimension {any}", .{
                    dim,
                    lower,
                });
                within_size = dim.cmp(&lower) != std.math.Order.lt;
                logger.debug("result of cmp is {any}", .{dim.cmp(&lower)});
            },
            .below => |upper| {
                logger.debug("checking if image dimension {any} is less than wanted dimension {any}", .{
                    dim,
                    upper,
                });
                within_size = !(dim.cmp(&upper) == std.math.Order.gt);
                logger.debug("result of cmp is {any}", .{upper.cmp(&dim)});
            },
            .between => |between| {
                logger.debug("checking if image dimension {any} is between wanted dimension {any} and {any}", .{
                    dim,
                    between.lower,
                    between.upper,
                });
                within_size =
                    between.lower.cmp(&dim) != std.math.Order.lt and dim.cmp(&between.upper) != std.math.Order.lt;
                logger.debug("result of cmp is lower: {any} and upper: {any}", .{
                    between.lower.cmp(&dim),
                    dim.cmp(&between.upper),
                });
            },
        },
    }
    logger.debug("image matched: {any}", .{within_size});
    return within_size;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
