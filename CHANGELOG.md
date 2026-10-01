# Changelog

## [1.0.12] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.0.11] - 2026-09-30

### Fixed
- `nextTeam` divided by zero when there were no teams.

### Changed
- The pot progression and the turn order move to `round.lua`.

### Added
- A spec walking the 1 2 4 8 16 32 run a team actually plays, and checking the
  turn order gives every team exactly one turn per cycle for any team count.
  The pot doubles, so an error in it is never small.

## [1.0.0]

### Added
- Initial release.
