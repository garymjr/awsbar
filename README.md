# AWSBar

AWSBar is a Swift Package Manager macOS menu bar app for working with AWS SSO profiles. It reads SSO profile metadata from `~/.aws/config`, shows the configured profiles in the menu bar, and provides quick actions for opening the AWS console, starting SSO login, copying profile exports, and switching the current profile.

## Features

- Lists AWS SSO profiles from `~/.aws/config`.
- Shows the selected account, role, and region in the menu.
- Opens the AWS access portal or AWS console for a selected profile.
- Starts `aws sso login --profile <name>` from the menu.
- Copies either `export AWS_PROFILE='<name>'` or the raw profile name.
- Polls the selected profile's credential status and changes the menu bar icon when credentials appear expired.
- Supports configurable credential refresh intervals and launch at login.

## Requirements

- macOS 14 or newer.
- Swift 5.9 or newer.
- AWS CLI v2 installed and available through one of the app's search paths:
  - `~/.local/share/mise/installs/awscli/latest/.mise-bins/aws`
  - `~/.local/bin/aws`
  - `/opt/homebrew/bin/aws`
  - `/usr/local/bin/aws`
  - `/usr/bin/aws`
  - or `aws` found through `/usr/bin/env`
- One or more AWS SSO profiles configured in `~/.aws/config`.

Use `mise` for local runtime management when available:

```sh
mise exec -- swift build
```

## AWS Configuration

AWSBar only displays profiles that look like SSO profiles. A profile is considered an SSO profile when it contains SSO account, role, start URL, or session settings.

Example:

```ini
[profile sandbox-admin]
sso_session = company
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1

[sso-session company]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1
```

The app does not store AWS credentials. It asks the AWS CLI for process-format credentials when checking status or building an AWS console sign-in URL.

## Build And Run

Build the SwiftPM executable:

```sh
mise exec -- swift build
```

Build a local `.app` bundle in `dist/` and launch it:

```sh
./script/build_and_run.sh
```

Build the bundle without launching:

```sh
./script/build_and_run.sh --build-only
```

Launch and verify that the `AWSBar` process is running:

```sh
./script/build_and_run.sh --verify
```

Stream app logs:

```sh
./script/build_and_run.sh --logs
```

Stream telemetry logs for the app bundle identifier:

```sh
./script/build_and_run.sh --telemetry
```

The build script writes generated output to `.build/` and `dist/`.

## Development

Application code lives in `Sources/AWSBar/`:

- `App/` contains the SwiftUI app entry point and app delegate.
- `Views/` contains the menu bar UI.
- `Models/`, `Stores/`, and `Services/` contain profile data, app state, AWS CLI integration, and console-opening behavior.
- `Support/` contains small reusable helpers.

There is currently no committed SwiftPM test target. For now, use a focused build as the baseline validation:

```sh
mise exec -- swift build
```

When adding testable parsing or helper behavior, add a `Tests/AWSBarTests/` target in `Package.swift` and keep tests away from live AWS calls.

## Security Notes

AWSBar works with AWS profile names, SSO metadata, temporary credentials returned by the AWS CLI, and AWS console sign-in URLs. Avoid logging or sharing profile names, account IDs, credentials, tokens, or screenshots that expose sensitive AWS information.

Do not commit generated output, local credentials, or AWS configuration files.
