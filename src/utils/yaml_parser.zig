const std = @import("std");
const testing = std.testing;
const yaml = @import("yaml");
const configs = @import("../app/config.zig");

const Allocator = std.mem.Allocator;

pub const YamlParseService = struct {
    arena: Allocator,
    file_path: []const u8,

    pub fn parse(arena: Allocator, file_path: []const u8) !configs.YamlCfgContainer {
        const ys = YamlParseService{
            .file_path = file_path,
            .arena = arena,
        };

        const loaded = try ys.loadYAML();
        return try ys.parseYAMLToStruct(loaded);
    }

    fn loadYAML(self: YamlParseService) !yaml.Yaml {
        std.log.debug("Parsing config file at {s}", .{self.file_path});
        const cwd = std.fs.cwd();
        const ten_mb = 10 * 1024 * 1024;
        const fileContents = try cwd.readFileAlloc(self.arena, self.file_path, ten_mb);
        defer self.arena.free(fileContents);

        std.log.debug("Loading conf file content", .{});
        var yamlParser = yaml.Yaml{ .source = fileContents };
        try yamlParser.load(self.arena);
        return yamlParser;
    }

    fn parseYAMLToStruct(self: YamlParseService, loaded: yaml.Yaml) !configs.YamlCfgContainer {
        std.log.debug("Loading conf to struct", .{});
        return try loaded.parse(self.arena, configs.YamlCfgContainer);
    }
};

test "parseTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    _ = try YamlParseService.parse(arena.allocator(), "./app.yaml");
}
