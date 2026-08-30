# Security Policy

## Scope

bashlog is a personal open source project rather than a commercially supported
security product.  The project nevertheless treats vulnerabilities and
security-boundary failures seriously, particularly because redaction is part of
bashlog's documented behavior.

The project's security claims are intentionally bounded.  `README.md`,
`doc/bashlog-spec.md`, the governing ADRs, and `doc/threat-model.md` describe what
bashlog protects, what it trusts, where data crosses boundaries, what evidence
supports the documented mitigations, and what remains outside its protection
boundary.

## Reporting a Vulnerability

Please do not disclose a suspected vulnerability in a public GitHub issue before
coordinated disclosure.

Send vulnerability reports to:

[security_vulnerability_disclosure@wesleydean.com](mailto:security_vulnerability_disclosure@wesleydean.com)

Useful reports include the affected bashlog version or commit, Bash version,
operating system, a minimal reproduction, expected behavior, actual behavior,
and the security impact.  Please avoid including real production credentials,
tokens, or private data when a synthetic reproducer will demonstrate the issue.

Good-faith attempts will be made to acknowledge, investigate, and address reports
within a reasonable period.  If communication stalls or a report remains
unresolved, please continue coordinating disclosure through the private contact
above rather than publishing sensitive technical details solely because a fixed
number of days has elapsed.

Once disclosure is appropriate, a public issue, advisory, release note, or other
public record may be created as part of the coordinated resolution.

## Security Expectations

Security-sensitive changes should preserve the project's documented fail-closed
boundaries, negative disclosure tests, pure-Bash runtime constraints, and explicit
limitations.  Changes that add dependencies, alter data-egress behavior, change
trust boundaries, or broaden security claims should also revisit
`doc/threat-model.md`.

A proposed fix that broadens a security claim should update the relevant ADR and
normative specification rather than relying on implementation behavior alone.
