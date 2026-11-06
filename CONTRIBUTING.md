# Contributing

Issues and pull requests are welcome.

* `RadarKit` holds everything testable. Add a test with a change: `swift test --package-path RadarKit`.
* After changing `project.yml`, run `xcodegen generate` and commit the project.
* New strings go in `scripts/l10n/source.py` with all nine languages. Then run `python3 scripts/l10n/source.py && python3 scripts/l10n.py`.
* Never add real customer or revenue data to tests, fixtures or screenshots. Use `--demo`.
