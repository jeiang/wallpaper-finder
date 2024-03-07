const std = @import("std");
const cli = @import("zig-cli");
const Dimensions = @import("utils.zig").Dimensions;
const setLogLevel = @import("log.zig").setLogLevel;

const logger = std.log.scoped(.config);

pub const RelativeSize = enum {
    smaller,
    larger,
    approx,
};
const RawConfig = struct {
    paths: []const []const u8 = &.{},
    ratio: ?[]const u8 = null,
    resolution: ?[]const u8 = null,
    tolerance: f32 = 5.0,
    relative_size: RelativeSize = .approx,
    log_level: std.log.Level = .err,
    skip_extension_check: bool = false,
};
pub fn Bounds(comptime T: type) type {
    return union(enum) {
        above: T,
        below: T,
        between: struct {
            upper: T,
            lower: T,
        },
    };
}
pub const ComparisonBounds = union(enum) {
    aspect_ratio: Bounds(f64),
    resolution: Bounds(Dimensions(f64)),
};
pub const Config = struct {
    paths: []const []const u8,
    size: ComparisonBounds,
    skip_extension_check: bool,
};
pub const ConfigError = error{
    InvalidTolerance,
    MissingResolutionOrRatio,
    InvalidRatio,
    InvalidResolution,
};

var raw_config = RawConfig{};
var config: ?Config = null;

pub fn GetConfig() ConfigError!Config {
    if (config) |completed_config| {
        logger.debug("returning completed config.", .{});
        return completed_config;
    }
    setLogLevel(raw_config.log_level);
    if (raw_config.ratio == null and raw_config.resolution == null) {
        logger.err("either resolution or ratio must be specified", .{});
        return ConfigError.MissingResolutionOrRatio;
    }
    if (raw_config.tolerance > 100 or raw_config.tolerance < 0) {
        logger.err("tolerance must be between 0 and 100. got {e}", .{raw_config.tolerance});
        return ConfigError.InvalidTolerance;
    }

    const upper_tolerance = (100 + raw_config.tolerance) / 100;
    const lower_tolerance = (100 - raw_config.tolerance) / 100;
    logger.debug("tolerance: {e} (upper: {e}, lower: {e})", .{
        raw_config.tolerance,
        upper_tolerance,
        lower_tolerance,
    });

    var bounds: ComparisonBounds = undefined;
    if (raw_config.resolution) |resolution_str| {
        logger.debug("parsing resolution: {s}.", .{resolution_str});
        const idx = std.mem.indexOfScalar(u8, resolution_str, 'x') orelse {
            logger.err("resolution string must be specified as <height>x<width>. got {s}", .{resolution_str});
            return ConfigError.InvalidRatio;
        };
        logger.debug("found x at idx {d}", .{idx});
        const width_str = resolution_str[0..idx];
        const height_str = resolution_str[(idx + 1)..(resolution_str.len)];
        logger.debug("height parsed as \"{s}\" and width string parsed as \"{s}\"", .{ height_str, width_str });
        const width = std.fmt.parseFloat(f64, width_str) catch |err| {
            logger.err("failed to parse width because {!} (input: {s})", .{ err, width_str });
            return ConfigError.InvalidRatio;
        };
        const height = std.fmt.parseFloat(f64, height_str) catch |err| {
            logger.err("failed to parse height because {!} (input: {s})", .{ err, width_str });
            return ConfigError.InvalidRatio;
        };
        logger.debug("height parsed as {d} and width parsed as {d}", .{ height, width });

        if (width == 0) {
            logger.err("width cannot be 0 for resolution", .{});
            return ConfigError.InvalidRatio;
        }
        if (height == 0) {
            logger.err("height cannot be 0 for resolution", .{});
            return ConfigError.InvalidRatio;
        }
        bounds = .{
            .resolution = switch (raw_config.relative_size) {
                .smaller => Bounds(Dimensions(f64)){
                    .below = Dimensions(f64){
                        .height = height,
                        .width = width,
                    },
                },
                .larger => Bounds(Dimensions(f64)){
                    .above = Dimensions(f64){
                        .height = height,
                        .width = width,
                    },
                },
                .approx => Bounds(Dimensions(f64)){
                    .between = .{
                        .lower = Dimensions(f64){
                            .height = height * lower_tolerance,
                            .width = width * lower_tolerance,
                        },
                        .upper = Dimensions(f64){
                            .height = height * upper_tolerance,
                            .width = width * upper_tolerance,
                        },
                    },
                },
            },
        };
        logger.debug("bounds parsed as {any}", .{bounds});
    } else if (raw_config.ratio) |ratio_str| {
        logger.debug("parsing ratio: {s}.", .{ratio_str});
        const idx = std.mem.indexOfScalar(u8, ratio_str, 'x') orelse {
            logger.err("aspect ratio string must be specified as <height>x<width>. got {s}", .{ratio_str});
            return ConfigError.InvalidRatio;
        };
        logger.debug("found x at idx {d}", .{idx});
        const width_str = ratio_str[0..idx];
        const height_str = ratio_str[(idx + 1)..(ratio_str.len)];
        logger.debug("height parsed as \"{s}\" and width string parsed as \"{s}\"", .{ height_str, width_str });
        const width = std.fmt.parseFloat(f64, width_str) catch |err| {
            logger.err("failed to parse width because {!} (input: {s})", .{ err, width_str });
            return ConfigError.InvalidRatio;
        };
        const height = std.fmt.parseFloat(f64, height_str) catch |err| {
            logger.err("failed to parse height because {!} (input: {s})", .{ err, height_str });
            return ConfigError.InvalidRatio;
        };
        logger.debug("height parsed as {d} and width parsed as {d}", .{ height, width });
        if (width == 0) {
            logger.err("width cannot be 0 in aspect ratio", .{});
            return ConfigError.InvalidRatio;
        }
        if (height == 0) {
            logger.err("height cannot be 0 in aspect ratio", .{});
            return ConfigError.InvalidRatio;
        }
        const ratio = width / height;
        logger.debug("ratio calculated as {e}", .{ratio});
        bounds = .{
            .aspect_ratio = switch (raw_config.relative_size) {
                // no idea why anyone would want anything other than approx but shrug emoji
                .smaller => Bounds(f64){
                    .below = ratio,
                },
                .larger => Bounds(f64){
                    .above = ratio,
                },
                .approx => Bounds(f64){
                    .between = .{
                        .lower = ratio * lower_tolerance,
                        .upper = ratio * upper_tolerance,
                    },
                },
            },
        };
        logger.debug("bounds parsed as {any}", .{bounds});
    } else {
        unreachable;
    }

    const paths = blk: {
        logger.debug("handling paths: {s}", .{raw_config.paths});
        if (raw_config.paths.len != 0) {
            break :blk raw_config.paths;
        } else {
            logger.debug("using cwd as root search path", .{});
            break :blk &[_][]const u8{"."};
        }
    };
    config = Config{
        .paths = paths,
        .size = bounds,
        .skip_extension_check = raw_config.skip_extension_check,
    };
    return config.?;
}

var cli_paths = cli.PositionalArg{
    .name = "PATHS",
    .help = "The paths to search",
    .value_ref = cli.mkRef(&raw_config.paths),
};

var cli_ratio = cli.Option{
    .long_name = "ratio",
    .short_alias = 'r',
    .help =
    \\ the ratio between the width and height (e.g. 16x9 for landscape 1920x1080 and 1:2 for portrait 1440x2880)
    \\ overriden by resolution
    ,
    .value_ref = cli.mkRef(&raw_config.ratio),
};

var cli_resolution = cli.Option{
    .long_name = "resolution",
    .short_alias = 's', // TODO: better alias
    .help =
    \\ the resolution of the image to compare against (e.g. 1920x1080 or 2560x1440)
    \\ overrides ratio
    ,
    .value_ref = cli.mkRef(&raw_config.resolution),
};

var cli_tolerance = cli.Option{
    .long_name = "tolerance",
    .short_alias = 't',
    .help =
    \\ how close a file's dimensions should be to the provided resolution or ratio as a percent
    \\ default is 5%
    ,
    .value_ref = cli.mkRef(&raw_config.tolerance),
};

var cli_relative_size = cli.Option{
    .long_name = "compare",
    .short_alias = 'c',
    .help =
    \\ whether the output images should be larger, smaller, or approx the same as the resolution
    \\ approx uses tolerance to find matches. default = approx
    ,
    .value_ref = cli.mkRef(&raw_config.relative_size),
};

var cli_log_level = cli.Option{
    .long_name = "log",
    .short_alias = 'l',
    .help =
    \\ log level (err, warn, info, debug)
    ,
    .envvar = "LOG",
    .value_ref = cli.mkRef(&raw_config.log_level),
};

var cli_skip_extension_check = cli.Option{
    .long_name = "skip-extension-check",
    .help =
    \\ do not try to match known file extensions, just read the file signature and try to match
    ,
    .value_ref = cli.mkRef(&raw_config.skip_extension_check),
};

var app: cli.App = undefined;

pub fn CreateApp(entrypoint: cli.ExecFn) *cli.App {
    app = cli.App{
        .command = cli.Command{
            .name = "wallpaper-finder",
            .description = cli.Description{
                .one_line = "Finds wallpapers by aspect ratio or resolution",
            },
            .options = &.{
                &cli_ratio,
                &cli_resolution,
                &cli_tolerance,
                &cli_relative_size,
                &cli_log_level,
                &cli_skip_extension_check,
            },
            .target = cli.CommandTarget{
                .action = cli.CommandAction{
                    .positional_args = cli.PositionalArgs{
                        .args = &.{&cli_paths},
                    },
                    .exec = entrypoint,
                },
            },
        },
    };
    return &app;
}
