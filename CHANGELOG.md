# Changelog

All notable changes to this action are documented here. Versions follow
[SemVer](https://semver.org/); `v1` always points at the latest `v1.x.y`.

## [Unreleased]

### Added
- Exact coverage statement in the README (`AWS fully supported · Azure in BETA · GCP
  roadmap`) and an explicit BETA caveat on the Azure usage section.
- Explicit "never modifies your account" statement in the README — detection and
  recommendations only, no remediation code path.
- A single, non-pushy "see it on your dashboard" link in the PR comment's success
  footer, carrying `utm_source=github_action&utm_medium=pr_comment` so hosted-account
  signups from the Action are attributable. Not shown on a failed-scan comment.
- Negative test asserting the failed-scan comment never carries the dashboard upsell
  link, alongside the positive test for the link on a successful scan.

## [1.4.0] - 2026-08-01
### Added
- Azure support: forward `AZURE_*` credentials (service-principal secret or OIDC
  federated-token file) into the scan container.

## [1.3.0] - 2026-07-22
### Changed
- Developer-friendly README rewrite; relicensed to Apache-2.0; added brand banner.
- First version published as a GitHub Release / Marketplace listing.

## [1.2.0] - 2026-07-21
### Added
- Sticky PR comment: re-running on the same PR updates the existing comment (matched
  via a hidden `<!-- cca-scan-results -->` marker) instead of stacking a new one.
- Distinguish a failed scan from a clean "0 findings" result (`scan-status` output,
  `::error::` annotation, dedicated failure comment, `fail-on-scan-error` input).

## [1.1.2] - 2026-07-21
### Fixed
- Pass the CCA API key via environment variable only — never on the command line —
  so it can't leak into `ps` output or shell history.

## [1.1.1] - 2026-07-21
### Added
- LICENSE; hardened composite-action inputs against shell/script injection by binding
  all inputs to `env:` instead of interpolating them into script text.

## [1.1.0] - 2026-06-29
### Fixed
- De-brittled output parsing (switched to `jq`), fixed action outputs, pinned the
  runner.

## [1.0.0] - 2026-06-03
### Changed
- Switched to the Docker-container scan model; fixed output parsing.

Initial release: 3-line CI integration that pulls the CCA container, scans AWS, and
reports findings.
