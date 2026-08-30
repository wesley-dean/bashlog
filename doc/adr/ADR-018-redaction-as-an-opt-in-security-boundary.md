# ADR-018: Redaction as an Opt-In Security Boundary

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This ADR establishes the security meaning of redaction in bashlog.

The decision is intentionally verbose because redaction can easily create false
confidence when its guarantees are stated imprecisely.  The project does not want
language such as "bashlog keeps secrets safe" when the Bash runtime cannot support
such a broad claim.  It also does not want the opposite failure mode, where
redaction is described so casually that a caller cannot tell whether a registered
secret is actually treated as a security obligation.

The project therefore adopts a narrow but strong position:

> Redaction is an opt-in defense-in-depth facility.  bashlog does not determine
> what developers may log.  Once a developer explicitly entrusts a value or
> pattern to the redaction facility, however, bashlog treats preventing matching
> sensitive content from reaching a bashlog logging sink as a security boundary
> and handles the entrusted rule accordingly.

The scope and limitations of that sentence are part of the architecture.

## Context

Logging is useful precisely because it carries context.  The same contextual
richness creates risk when passwords, API keys, tokens, private keys, session
identifiers, personal data, or other sensitive information enter log messages.

The strongest protection remains avoiding unnecessary sensitive data in logging
code.  A logging library cannot determine universally which application values
are sensitive, and heuristics that guess based on names or formats can both miss
real secrets and redact harmless data.

bashlog therefore does not attempt to decide what is sensitive on behalf of the
application.  The developer makes that decision explicitly by registering a
redaction rule.

Once the developer has done so, however, the meaning changes.  A registered
password cannot be treated as a best-effort decoration where a matching failure,
invalid pattern, unexpected replacement string, or unusual log level simply
causes the original message to be printed.  The registered rule has become part
of the logging security boundary.

Bash complicates this design in several ways:

- Bash has no secure-memory primitive for shell variables.
- Bash may copy variable contents internally.
- Code executing in the same interpreter can inspect shell state.
- Bash regular-expression matching reports matched text but does not provide a
  general high-level replacement API with all the semantics this project needs.
- parameter substitution has pattern and replacement semantics that must not be
  confused with literal secret handling;
- newer Bash versions introduce additional replacement behavior such as
  `patsub_replacement`, so replacement safety cannot rely on casual assumptions;
- shell tracing can expose expanded function arguments before a function gains
  control;
- and invalid or zero-length patterns can create dangerous failure behavior if
  not handled deliberately.

These constraints do not make useful redaction impossible.  They require the
project to say exactly what boundary it can defend.

## Decision Drivers

- Prevent explicitly registered sensitive values from accidental disclosure
  through bashlog output.
- Avoid pretending that bashlog can discover sensitivity automatically.
- Fail closed when required redaction cannot be completed safely.
- Keep registered sensitive data inside the current Bash process rather than
  intentionally transmitting it to helper commands.
- Avoid public APIs whose purpose is to retrieve registered secret values.
- Ensure replacement text cannot become a secondary evaluation or expansion
  language.
- Apply redaction to every bashlog-provided logging level and sink.
- Document runtime limitations honestly, especially the lack of private or secure
  memory.
- Make failure diagnostics safe even when redaction itself fails.
- Preserve enough specificity that tests can prove absence of known secrets from
  observable output.

## Decision

bashlog SHALL provide explicit redaction configuration and SHALL treat accepted
redaction rules as security-sensitive state.

Redaction is opt-in.  bashlog SHALL NOT heuristically infer that arbitrary values
are passwords, tokens, personally identifiable information, or other secrets.
The developer remains responsible for deciding what data should be registered
for redaction and, more fundamentally, what data should be sent to logging code
at all.

Once a redaction rule has been accepted by the public API, every bashlog output
path governed by that configuration MUST honor the rule according to its
specified matcher semantics before emitting sink-bound text.

### Fail-Closed Behavior

If bashlog cannot complete required redaction safely, it SHALL NOT emit the
original sink-bound message as a fallback.

A redaction failure MAY produce a fixed diagnostic indicating that a log message
was suppressed, but that diagnostic MUST be constructed without including the
original message, the registered sensitive value, the sensitive pattern, or
other redaction state that could recreate the disclosure.

The precise diagnostic wording and return status belong to the normative
specification.  The security rule is independent of wording:

> Failure to redact is a reason to suppress the original output, not permission
> to emit it unchanged.

### Literal Replacement Invariant

Replacement text supplied to the redaction facility SHALL always be treated as
opaque literal text.

bashlog SHALL NOT interpret replacement strings as:

- shell code;
- parameter expansion;
- command substitution;
- arithmetic expansion;
- glob expansion;
- regular-expression backreferences;
- `&`-style matched-text substitution;
- escape sequences;
- or any other secondary expression language.

If the configured replacement is:

```text
[REDACTED PASSWORD]
```

then those exact characters are the intended replacement.

If the configured replacement contains characters such as `&`, `\1`, `$()`,
`${NAME}`, `*`, `?`, `[`, or `]`, those characters remain data unless a later ADR
explicitly introduces a **different** API with different semantics.  The ordinary
redaction replacement contract itself will not silently acquire interpretation.

### Public Exposure of Redaction State

The public API SHALL NOT provide a general getter, list command, serializer, or
other interface whose purpose is to return registered sensitive values to the
caller.

This is not described as access control; same-process Bash code can inspect shell
state if it chooses.  The purpose is to avoid manufacturing an accidental
exfiltration interface in the library's supported contract.

Non-sensitive metadata, such as whether a context exists or how many rules it
contains, MAY be considered later if useful and if it cannot expose sensitive
rule content.

### Persistence and Process Boundaries

bashlog SHALL NOT intentionally persist redaction secrets to files, caches, or
other durable storage as part of its runtime operation.

bashlog SHALL NOT export redaction state into the process environment for child
processes.

bashlog SHALL NOT transmit unredacted redaction state to external helper commands.
ADR-014 independently prohibits runtime external-command execution, reinforcing
this boundary.

### Same-Process Reality

Registered fixed values necessarily require bashlog to retain enough plaintext
information in the current Bash process to identify that value in log text.
The project SHALL state that fact plainly.

bashlog does not have a language mechanism that can make such values private from
other code executing in the same Bash process.  Internal naming conventions are
not security controls.

The defensible claim is therefore:

> bashlog retains the plaintext necessary to perform exact fixed-string
> redaction, keeps that state within the current Bash process, does not
> intentionally expose it through its public interface, diagnostics, persistence,
> environment export, or external helper programs, and prevents accepted rules
> from being bypassed by bashlog's own logging paths.

The project SHALL NOT claim secure memory, guaranteed zeroization, or protection
from hostile same-process code.

### Shell Tracing

Caller-side tracing such as `set -x` can expose expanded arguments before a
bashlog function controls them.  For example, a call that passes a secret as a
function argument may be printed by Bash tracing at the call site.

bashlog SHALL document this boundary prominently.  Internal implementation SHOULD
avoid creating additional trace exposure where practical, but the library SHALL
NOT claim that it can undo caller-side xtrace disclosure that already occurred.

## Promises

Subject to the documented matcher semantics and threat boundary, bashlog makes
the following redaction promises:

1. **Explicitly accepted rules are security obligations.**  A registered
   redaction rule is not merely a presentation preference.

2. **Required redaction precedes every bashlog sink.**  No bashlog severity,
   verbosity path, convenience helper, or built-in sink may intentionally bypass
   configured redaction.

3. **Redaction failure suppresses the original message.**  bashlog does not
   respond to a redaction-processing failure by emitting the unredacted input.

4. **Failure diagnostics do not echo protected material.**  A redaction failure
   diagnostic does not include the original message or registered sensitive
   values merely to explain the failure.

5. **Replacement text is literal.**  Ordinary replacement strings are never
   interpreted as code, expansion syntax, backreferences, or matched-text
   placeholders.

6. **No public secret retrieval interface.**  bashlog does not intentionally
   provide a supported public operation for retrieving registered sensitive
   values.

7. **No intentional runtime persistence or child-process export.**  bashlog does
   not intentionally write registered secrets to persistent storage or export
   them to child-process environments.

8. **No external redaction helper.**  Unredacted state is not intentionally sent
   to `sed`, `awk`, hashing tools, or other helper processes by bashlog.

9. **The limitations are part of the promise.**  bashlog documents the actual
   boundary rather than representing redaction as general secret management.

## Non-Promises

bashlog explicitly does **not** promise the following:

1. **Automatic sensitivity detection.**  bashlog does not decide which values are
   secrets or personally identifiable information.

2. **Permission to log indiscriminately.**  Redaction is defense in depth.  The
   preferred design remains avoiding unnecessary sensitive data in logs.

3. **Secure memory.**  Bash does not provide secure-memory allocation, locking,
   or reliable zeroization semantics suitable for such a claim.

4. **Protection from hostile same-process code.**  Code executing in the same
   Bash interpreter can inspect variables, functions, and other process state.

5. **Protection from privileged memory inspection.**  bashlog does not claim
   resistance to debuggers, `ptrace`, `/proc` memory access, core dumps,
   compromised kernels, root, or equivalent operating-system privilege.

6. **Protection from a compromised Bash runtime.**  Bash itself is part of the
   trusted computing base for this library.

7. **Protection from caller-side xtrace.**  bashlog cannot prevent Bash from
   tracing expanded arguments before control enters the logging function.

8. **Protection for data already emitted elsewhere.**  A value printed by the
   caller or another library before bashlog sees it cannot be retroactively
   removed.

9. **General secret-management functionality.**  bashlog is not a vault,
   credential manager, encryption system, or secure enclave.

10. **Unicode semantic equivalence.**  Exact fixed-string redaction is expected to
    protect the exact sequence supplied by the caller; the project does not
    promise Unicode normalization equivalence unless a later ADR explicitly adds
    such behavior.

11. **Unspecified matcher behavior.**  Fixed, glob, and ERE rules will receive
    explicit contracts.  This ADR does not claim that all matcher types have
    identical Unicode, locale, or zero-length-match semantics.

## Adversary and Failure Model

### Conditions the Design Intentionally Accounts For

The redaction architecture is intended to protect against accidental disclosure
through bashlog when:

- a developer intentionally registers a known secret and later includes that
  value in a formatted log message;
- the secret appears more than once;
- the secret is adjacent to other text;
- the secret appears in caller-controlled metadata that bashlog includes in the
  final line;
- a log message is emitted through debug, info, warning, error, or another
  supported severity;
- a higher-level helper such as `bashlog_die` logs before terminating;
- a redaction matcher is invalid or cannot be processed safely;
- replacement text contains characters that would have special meaning to shell
  or pattern-substitution mechanisms;
- a presentation option, renderer, or sink is added later;
- a failure path is tempted to print the original message for diagnostics;
- and implementation refactoring changes internal functions but should not change
  the output boundary.

The project will also test multibyte fixed-string behavior using representative
UTF-8 values.  The exact contract for fixed versus glob/ERE matching will be
recorded separately.

### Conditions Outside the Protection Boundary

The design does not claim protection against:

- malicious code already executing in the same Bash interpreter;
- deliberate inspection of bashlog's shell variables by same-process code;
- debugger, root, kernel, or equivalent privileged memory access;
- a compromised Bash interpreter;
- caller-side `set -x` disclosure before function entry;
- a caller that bypasses bashlog and prints a secret directly;
- another logging library or external command receiving the secret separately;
- a secret that was emitted before its redaction rule was registered;
- or semantic equivalence between distinct Unicode sequences unless explicitly
  specified later.

### Trust Model

The project does not ask consumers to accept a generic assertion that registered
secrets are "safe."  Trust should follow from observable, reviewable behavior:

- the redaction path is implemented in readable Bash;
- the library does not invoke external runtime commands;
- the public API does not return registered secret values;
- failure does not fall back to original output;
- diagnostics are designed not to echo protected state;
- tests assert the **absence** of registered values from observable logging
  output;
- and limitations are documented with the same prominence as guarantees.

## Operational Constraints

- Redaction MUST be explicitly configured by the caller; bashlog MUST NOT rely on
  heuristic sensitive-data detection as its security contract.
- Once a rule is accepted, every bashlog sink governed by that configuration MUST
  honor it according to the rule's documented matcher semantics.
- Redaction processing failure MUST NOT emit the original message.
- Redaction failure diagnostics MUST NOT include the original message or
  registered sensitive values.
- Ordinary replacement strings MUST be literal and MUST NOT support evaluation,
  expansion, `&` substitution, or backreferences.
- The public API MUST NOT provide a general operation whose purpose is to return
  registered secret values.
- bashlog MUST NOT intentionally persist registered secret values at runtime.
- bashlog MUST NOT export registered redaction state to child-process
  environments.
- bashlog MUST NOT invoke external helper commands for runtime redaction.
- Documentation MUST explicitly state that Bash does not provide secure memory
  or protection from hostile same-process code.
- Documentation MUST explicitly warn that caller-side xtrace may expose expanded
  arguments before bashlog can redact them.
- Tests MUST include negative assertions demonstrating that protected values do
  not appear in stdout, stderr, or redaction failure diagnostics for covered
  behaviors.
- New logging sinks or severity paths MUST demonstrate that they pass through the
  common final redaction boundary.

## Considered Alternatives

### Do Not Provide Redaction

The project could remain a conventional logger and require callers to sanitize
all messages before calling it.

This would keep bashlog smaller, but it would discard the defense-in-depth
capability that motivated the project.  Centralized logging is an effective place
to enforce explicitly configured final-output redaction because all library
sinks can converge through one boundary.

### Automatically Guess Which Values Are Sensitive

bashlog could inspect variable names, key names, or string formats for words such
as `password`, `token`, or patterns resembling common identifiers.

It was rejected as the primary model because sensitivity is application-specific
and heuristic detection produces both false positives and false negatives.  A
security promise should not depend on guesses about the caller's data model.

### Treat Redaction as Best Effort and Emit on Failure

If a matcher fails, bashlog could warn and print the original message so logging
availability is preserved.

It was rejected because a registered redaction rule represents an explicit
security decision.  Once that decision exists, logging availability is less
important than preventing the known disclosure.  Suppression is the safer
failure mode.

### Store Only Hashes of Fixed Secrets

This appears attractive because the library would not retain the plaintext
secret in obvious shell state.

It was rejected because a hash does not reveal where the plaintext occurs inside
an arbitrary message.  Generic matching would require generating candidate
substrings and hashing them, which is expensive, length-sensitive, and still
problematic for low-entropy secrets.  Bash also lacks native SHA-256 at the
current compatibility floor, which would violate the no-external-command runtime
boundary.

### Obfuscate or Encode Registered Secrets Internally

Base64, reversible encoding, mangled variable names, or similar techniques could
make casual inspection less obvious.

It was rejected because reversible representation does not create a security
boundary and would conflict with the project's inspectability requirement.  It
would be security theater: additional complexity without meaningful isolation.

### Isolate Redaction in a Subshell or Long-Lived Helper Process

A subprocess could hold redaction state separately from the caller's main shell.

It was rejected for the initial architecture because the apparent isolation is
modest relative to the complexity introduced: IPC, buffering, synchronization,
signal handling, lifecycle management, failure recovery, output ordering, and
new process boundaries.  It would also conflict with the pure-Bash/no-external-
command simplicity of the chosen design and make the security path substantially
harder to understand.

### Provide `get` or `list` Operations for Redaction Rules

Introspection would make debugging configuration convenient.

It was rejected as a general secret-value interface because it creates a
supported path whose purpose is to reproduce sensitive state after registration.
The project may later expose non-sensitive metadata if it can do so without
returning protected content.

### Support Backreferences or Matched-Text Substitution in Replacement Strings

Powerful regex replacement languages commonly support `\1` or `&` semantics.

It was rejected for the ordinary redaction API because replacement text should be
data, not another expression language.  If capture-based transformation is ever
needed, it should be a distinct API with its own security model rather than a
silent complication of redaction replacement.

## Consequences

The fail-closed model may intentionally suppress useful diagnostic messages when
redaction configuration is invalid or processing cannot be completed.  That is
an accepted tradeoff.  A logger entrusted with an explicit secret should not
choose observability over the security obligation without caller consent.

The library will retain plaintext fixed-string values in Bash memory while those
rules are active.  Documentation must resist euphemisms about that fact.

Testing becomes more demanding.  Redaction tests need to look not only for the
expected replacement but also for forbidden originals across all observable
outputs and failure paths.

The design constrains future optimization.  Any faster or shorter implementation
must preserve the same failure behavior, literal replacement semantics, and
output boundary.

## Source Lineage

This decision is informed by repository-security guidance that treats avoidance
of sensitive logging as the primary protection and redaction as secondary
defense in depth.

It also incorporates the trust-boundary, no-external-command, and readability
principles developed for bashlog, as well as the broader project family's
preference for explicit and testable guarantees over vague claims.

## Open Questions and Follow-Ups

The following details intentionally remain for narrower ADRs:

- redaction context creation and naming;
- whether contexts are append-only from creation until destruction;
- whether a context may be sealed after first use;
- whether one-way context destruction is provided and how its limitations are
  described without claiming secure erasure;
- fixed, glob, and ERE registration syntax;
- exact fixed-string global replacement algorithm;
- glob and ERE locale/multibyte semantics;
- invalid and zero-length ERE behavior;
- duplicate rules and ordering;
- empty patterns and empty replacements;
- unknown-context behavior;
- and whether a final verification pass against every configured fixed secret is
  required after all transformations to defend against later rules or replacement
  text reintroducing a protected value.

These questions must be resolved before implementation is considered complete.
They are not permission for implementation to choose semantics accidentally.

## Related Decisions

- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-019: Readability, Auditability, and Rejection of Obscurity
