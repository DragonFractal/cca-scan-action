# 💰 CCA Cost Scan — GitHub Action

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-CCA%20Cost%20Scan-2088FF?logo=github)](https://github.com/marketplace/actions/cca-cost-scan)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Powered by Cloud Cost Analyzer](https://img.shields.io/badge/Powered%20by-Cloud%20Cost%20Analyzer-blue)](https://cca.dragonfractal.com)

Scan your cloud infrastructure for cost-optimization opportunities straight from CI, and get the savings posted right on your pull request — powered by [**Cloud Cost Analyzer (CCA)**](https://cca.dragonfractal.com).

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
```

That one step pulls the CCA container, scans your AWS account, and comments a findings summary on the PR. No install, no config files.

---

## Contents

- [Why](#why)
- [Get started in 3 steps](#get-started-in-3-steps)
- [Prerequisites](#prerequisites)
- [Usage examples](#usage-examples)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [The PR comment](#the-pr-comment)
- [When a scan fails](#when-a-scan-fails)
- [How it works](#how-it-works)
- [Documentation & support](#documentation--support)
- [License](#license)

---

## Why

- **Catch waste before it ships.** Idle instances, unattached volumes, oversized databases — surfaced on the PR that introduces them.
- **Zero footprint.** Runs as a container; nothing to install into your repo or runners beyond Docker.
- **Actionable.** Every finding comes with an estimated monthly saving, ranked highest-first.
- **CI-native.** Standard inputs/outputs, a sticky PR comment, and an optional failure threshold to gate merges.

## Get started in 3 steps

1. **Create a CCA account** and generate an API key from your dashboard at **[cca.dragonfractal.com](https://cca.dragonfractal.com)**. (See [Getting Started](https://cca.dragonfractal.com/docs) for the walkthrough.)
2. **Add the key as a repository secret** named `CCA_API_KEY`
   → *Settings → Secrets and variables → Actions → New repository secret*.
3. **Add the workflow** below. That's it.

```yaml
name: Cost Scan
on: [pull_request]

permissions:
  id-token: write        # to assume your AWS role via OIDC
  contents: read
  pull-requests: write   # to post the results comment

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Provide AWS credentials however you already do — OIDC role recommended.
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - uses: dragonfractal/cca-scan-action@v1
        with:
          api-key: ${{ secrets.CCA_API_KEY }}
```

## Prerequisites

| Need | How |
|------|-----|
| **A CCA API key** | Sign up at [cca.dragonfractal.com](https://cca.dragonfractal.com) and create one in your dashboard. Store it as the `CCA_API_KEY` secret. |
| **AWS credentials** | Configure them in the job before this step — an OIDC role via [`aws-actions/configure-aws-credentials`](https://github.com/aws-actions/configure-aws-credentials) is recommended. The action reads the standard `AWS_*` environment variables. |
| **Read-only access** | The scan only needs read/describe + Cost Explorer permissions. Grant a **read-only** role — never deploy credentials. See the [permissions guide](https://cca.dragonfractal.com/docs). |
| **`pull-requests: write`** | Required for the PR comment. Omit only if you set `comment-on-pr: 'false'`. |
| **Docker on the runner** | Provided on GitHub-hosted `ubuntu-latest`. Self-hosted runners must have Docker available. |

## Usage examples

### Comment cost findings on every PR

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
```

### Fail the build when there are too many findings

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
    fail-on-findings: '20'   # fail if more than 20 findings
```

### Scheduled weekly scan (no PR comment)

```yaml
name: Weekly Cost Scan
on:
  schedule:
    - cron: '0 9 * * 1'   # Mondays at 09:00 UTC

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - uses: dragonfractal/cca-scan-action@v1
        with:
          api-key: ${{ secrets.CCA_API_KEY }}
          comment-on-pr: 'false'
```

### Scan specific regions and use outputs

```yaml
- uses: dragonfractal/cca-scan-action@v1
  id: cca
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
    regions: us-east-1,us-west-2

- name: Show results
  run: |
    echo "Findings: ${{ steps.cca.outputs.findings-count }}"
    echo "Savings:  \$${{ steps.cca.outputs.total-savings }}/mo"
    echo "Status:   ${{ steps.cca.outputs.scan-status }}"
```

> **Tip:** pin to the moving major tag `@v1` to get non-breaking updates automatically, or pin an exact release like `@v1.3.0` for full reproducibility.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | **Yes** | — | Your CCA API key ([get one](https://cca.dragonfractal.com)). |
| `provider` | No | `aws` | Cloud provider to scan (`aws`, `azure`). |
| `regions` | No | *(all)* | Comma-separated regions, e.g. `us-east-1,us-west-2`. |
| `service-url` | No | `https://cca.dragonfractal.com` | CCA service endpoint. |
| `version` | No | `latest` | CCA container image tag. |
| `output-file` | No | `cca-scan-results.json` | Path for the JSON results file. |
| `comment-on-pr` | No | `true` | Post the summary as a PR comment (on `pull_request` events). |
| `fail-on-findings` | No | `0` | Fail the action if findings exceed this threshold (`0` = never). |
| `fail-on-scan-error` | No | `true` | Fail the action if the scan can't run at all (vs. finding nothing). |

## Outputs

| Output | Description |
|--------|-------------|
| `findings-count` | Number of findings detected. |
| `total-savings` | Total potential monthly savings, in USD. |
| `scan-status` | `ok` if the scan completed, `failed` if it could not run. |

## The PR comment

On `pull_request` events (and with `comment-on-pr` enabled, the default) the action posts a comment containing:

- a summary table — total findings and estimated monthly savings,
- the **top 10 findings** by savings, and
- a link back to Cloud Cost Analyzer.

The comment is **sticky**: subsequent runs on the same PR update the existing comment in place rather than stacking a new one on every push.

## When a scan fails

A scan that **can't run** — bad credentials, an unreachable service, a wrong image tag — is reported as a **failure**, never as a misleading "0 findings". When this happens the action:

- prints a clear `::error::` annotation with the likely cause,
- posts a **⚠️ Scan Failed** PR comment instead of a `$0 / 0 findings` result,
- sets `scan-status: failed`, and
- **fails the action** so it can't pass silently.

Prefer a visible warning over a hard failure? Set `fail-on-scan-error: 'false'` — the error annotation and comment still appear, but the run stays green. A scan that runs and genuinely finds nothing is always `ok`.

## How it works

The action is a lightweight composite wrapper. On each run it:

1. Pulls the CCA container image (`dragonfractal/cca:<version>`).
2. Runs a scan against your cloud account, using the AWS credentials already present in the job environment. Your API key is passed via the `CCA_API_KEY` environment variable — never on the command line.
3. Parses the JSON results to produce the action outputs, the PR comment, and the optional failure threshold.

No credentials or results leave your runner except the scan request to the CCA service you configure via `service-url`.

## Documentation & support

- 📖 **Documentation:** [cca.dragonfractal.com/docs](https://cca.dragonfractal.com/docs)
- 🖥️ **CLI installation:** [cca.dragonfractal.com/docs/cli/installation](https://cca.dragonfractal.com/docs/cli/installation)
- 🌐 **Cloud Cost Analyzer:** [cca.dragonfractal.com](https://cca.dragonfractal.com)
- 🐛 **Issues & requests:** [open an issue](https://github.com/DragonFractal/cca-scan-action/issues)

## License

[MIT](./LICENSE) © DragonFractal
