---
name: Bug report
about: Report reproducible bashlog behavior that differs from the documented contract
title: ""
labels: bug
assignees: ""
---

## Problem

Describe the behavior you observed and why it appears incorrect.

## Environment

- bashlog version, release, or commit:
- artifact sourced (`bashlog.dev.bash`, `bashlog.bash`, or `bashlog.min.bash`):
- Bash version (`bash --version`):
- operating system / distribution:
- relevant shell options or `shopt` settings, if any:
- is standard error attached to a TTY or redirected/captured?:

## Minimal Reproduction

Please provide the smallest Bash program that reproduces the problem.  Use
synthetic values rather than real credentials, tokens, or private data.

```bash
# reproduction
```

## Expected Behavior

What did you expect bashlog to do?  If applicable, identify the relevant section
of `doc/bashlog-spec.md` or README.

## Actual Behavior

Include the exit status and distinguish standard output from standard error when
that matters.

```text
stdout:

stderr:

status:
```

## Configuration

Include relevant bashlog configuration, such as level threshold, renderer,
timestamp mode, color mode, severity style overrides, tags, and whether a
redaction context was explicitly selected.

## Additional Context

Add any other information that would help reproduce or understand the problem.

Do not report suspected vulnerabilities or include sensitive information in this
public template.  Follow `SECURITY.md` for security reports.
