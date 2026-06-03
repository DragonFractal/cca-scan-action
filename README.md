# CCA Scan Action

Scan your cloud infrastructure for cost optimization opportunities using [Cloud Cost Analyzer](https://cca.dragonfractal.com).

## Quick Start

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
```

That's it. The action installs CCA, runs a scan against your AWS account, and posts results as a PR comment.

## Usage

### Basic Scan

```yaml
name: Cost Scan
on: [pull_request]

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - uses: dragonfractal/cca-scan-action@v1
        with:
          api-key: ${{ secrets.CCA_API_KEY }}
```

### Full Configuration

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
    provider: aws
    regions: us-east-1,us-west-2
    output-format: json
    output-file: scan-results.json
    comment-on-pr: 'true'
    fail-on-findings: '50'
    version: v0.1.0
```

### Fail on Too Many Findings

```yaml
- uses: dragonfractal/cca-scan-action@v1
  with:
    api-key: ${{ secrets.CCA_API_KEY }}
    fail-on-findings: '20'  # Fail if more than 20 findings
```

### Scheduled Weekly Scan

```yaml
name: Weekly Cost Scan
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9am UTC

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

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | Yes | — | CCA API key ([get one here](https://cca.dragonfractal.com)) |
| `provider` | No | `aws` | Cloud provider (`aws`, `azure`) |
| `regions` | No | — | Comma-separated regions (e.g. `us-east-1,us-west-2`) |
| `service-url` | No | `https://cca.dragonfractal.com` | CCA service URL |
| `version` | No | `latest` | CCA CLI version |
| `output-format` | No | `json` | Output format (`table`, `json`, `yaml`, `markdown`) |
| `output-file` | No | `cca-scan-results.json` | Path to save results |
| `comment-on-pr` | No | `true` | Post summary as PR comment |
| `fail-on-findings` | No | `0` | Fail if findings exceed threshold (0 = never) |

## Outputs

| Output | Description |
|--------|-------------|
| `findings-count` | Number of findings detected |
| `total-savings` | Total potential monthly savings (USD) |
| `scan-id` | Scan ID from the managed backend |
| `optimization-score` | Infrastructure optimization score (0-100) |

## PR Comment

When `comment-on-pr` is enabled (default), the action posts a formatted comment on the PR with:

- Summary table (findings, savings, score)
- Top 10 findings by savings
- Link to the full report on the CCA dashboard

## Prerequisites

- AWS credentials configured (via `aws-actions/configure-aws-credentials` or environment variables)
- CCA API key (sign up at [cca.dragonfractal.com](https://cca.dragonfractal.com))

## Links

- [Cloud Cost Analyzer](https://cca.dragonfractal.com)
- [Documentation](https://cca.dragonfractal.com/docs)
- [CLI Installation](https://cca.dragonfractal.com/docs/cli/installation)
