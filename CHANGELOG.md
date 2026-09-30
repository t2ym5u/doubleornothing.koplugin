# Changelog

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
