# Contributing

## Principles

- Keep the main branch releasable.
- Prefer small, reviewable pull requests.
- Do not bypass failing CI without a clear reason.
- Keep gameplay-first priorities ahead of tooling-first polish.

## Local setup

1. Install Xcode.
2. Install `xcodegen`.
3. Clone the repository.
4. Run:

```bash
./scripts/bootstrap.sh
./scripts/generate_project.sh
./scripts/build.sh
./scripts/test.sh
```

## Standard commands

```bash
./scripts/generate_project.sh
./scripts/build.sh
./scripts/test.sh
./scripts/analyze.sh
```

## Branching

- Create a short-lived branch from `main`.
- Keep one concern per branch.
- Merge through pull requests when practical.

## Pull requests

- Link the relevant issue.
- Explain gameplay impact and technical impact separately.
- Include screenshots or short clips for UI/gameplay changes.
- Call out any skipped tests or platform-specific risks.

## Issue hygiene

- Use the provided issue templates.
- Keep epics large and outcome-oriented.
- Put implementation detail in child issues or pull requests, not in roadmap epics.
