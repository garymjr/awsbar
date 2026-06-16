# Repository Guidelines

## Project Structure & Module Organization

AWSBar is a Swift Package Manager macOS menu bar app targeting macOS 14.
Application source lives in `Sources/AWSBar/`, grouped by role:

- `App/` contains the SwiftUI entry point and app delegate.
- `Views/` contains menu bar UI.
- `Models/`, `Stores/`, and `Services/` contain profile data, state, AWS CLI integration, and console-opening behavior.
- `Support/` contains small reusable helpers such as shell quoting and menu title formatting.

`script/build_and_run.sh` builds a local `.app` bundle into `dist/`. Treat `.build/` and `dist/` as generated output.

## Build, Test, and Development Commands

Use `mise` for project-local tool versions when available.

- `mise exec -- swift build` builds the executable target.
- `mise exec -- swift test` runs SwiftPM tests when test targets are added.
- `./script/build_and_run.sh` builds `dist/AWSBar.app` and launches it.
- `./script/build_and_run.sh --verify` launches the app and checks that the `AWSBar` process is running.
- `./script/build_and_run.sh --logs` or `--telemetry` streams app logs for debugging.

## Coding Style & Naming Conventions

Follow the existing Swift style: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties and functions, and focused files named after the main type or responsibility. Keep SwiftUI view code in `Views/`, AWS process and network behavior in `Services/`, and small pure helpers in `Support/`.

Avoid broad abstractions unless they remove real duplication. Add comments only for non-obvious constraints, especially around shell execution, AWS credentials, or macOS app lifecycle behavior.

## Testing Guidelines

There is currently no committed SwiftPM test target. When adding tests, create a `Tests/AWSBarTests/` target in `Package.swift`, prefer focused unit tests for pure helpers and parsing logic, and name test files after the unit under test, for example `ShellQuotingTests.swift`.

For behavior touching AWS CLI execution, avoid live AWS calls in unit tests; isolate command construction, parsing, and error handling behind testable helpers.

## Commit & Pull Request Guidelines

Git history currently uses a short imperative subject, such as `Initial AWSBar app`. Keep commits concise and scoped to one change. Pull requests should include a brief summary, validation performed, screenshots or screen recordings for visible UI changes, and notes about any AWS CLI, macOS permission, or credential-handling implications.

## Security & Configuration Tips

Protect AWS profile names, credentials, tokens, and console sign-in URLs in logs and screenshots. Do not add dependencies without explicit approval; first check whether Swift, Foundation, AppKit, SwiftUI, or existing project code can solve the problem.
