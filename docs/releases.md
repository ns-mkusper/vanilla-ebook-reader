# Release workflow

Just Read It uses an alpha release channel for automated APK publishing.

## Versioning

Alpha releases use semver prerelease tags:

```text
v0.1.0-alpha.1
v0.1.0-alpha.2
v0.1.0-alpha.3
```

The base version comes from `flutter_client/pubspec.yaml`. The alpha number is generated from the latest existing `v<base>-alpha.N` tag.

## Trigger

The alpha release workflow runs after the `CI` workflow completes successfully on `main`. It can also be run manually with `workflow_dispatch`.

The release workflow is intentionally gated by CI rather than running directly on every push. A merge only publishes an artifact after the same commit has passed:

- `rust-lint-and-test`
- `android-rust-check`
- `flutter-ux-tests`
- `android-emulator-screenshots`

## Artifacts

Each alpha release publishes:

- an Android ARM64 debug APK;
- a SHA256 checksum file;
- release notes containing the release commit SHA, source CI run, artifact metadata, and a changelog.

The changelog is generated from the first-parent Git history. If a previous alpha tag exists, release notes list commits since that tag and include a compare link. For the first alpha release, notes include a bounded recent-commit summary.

The workflow tags the exact merge commit used for the build so the APK, source, changelog, and CI validation are traceable.

## Idempotency

If an alpha tag already points at the release commit, the workflow exits without creating a duplicate release. Historical alpha releases should remain immutable.

## Future production work

Alpha releases currently prioritize traceability and installable debug artifacts. Production release hardening should add:

- real Android signing credentials;
- Android App Bundle generation for Play Store distribution;
- explicit promotion from alpha to beta/stable;
- iOS artifacts after iOS compatibility lands.
