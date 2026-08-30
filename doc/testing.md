# Testing

The starter uses Bats for behavior-oriented tests and exercises every generated
artifact flavor.  The goal is to validate what consumers execute rather than
assume concatenation, comment stripping, or minification cannot change behavior.

Tests live under `tests/`.  Prefer a larger number of focused tests over a small
number of broad fixtures.  A failing test should normally identify one primary
contract.

`make test` runs the suite against the development, stripped, and minified
artifacts.  `make test-report` repeats the suite and writes JUnit XML under
`test-results/` for CI reporting.

The starter suite covers its own example behavior: help and version output,
build metadata, plugin discovery, noop execution, invalid plugin handling,
artifact shape, `.sha256` checksum companions, absence of stale `.256`
companions, and standalone runtime behavior.  A derived project should replace
or extend these examples with tests for its actual public contracts.

CI also plants legacy `.256` companions before a rebuild and verifies that a
successful `make build` removes them while preserving deterministic executable
bytes and valid `.sha256` companions.

Syntax validation and ShellCheck are part of `make check`, not substitutes for
behavior tests.  Release verification additionally checks exact artifact hashes
and minimum-Bash compatibility.
