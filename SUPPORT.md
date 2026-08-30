# Getting Support

bashlog is a sourceable Bash library.  If you encounter unexpected behavior,
please first check the following:

1. confirm that you are using Bash 4.3 or newer;
2. confirm which bashlog artifact or release you sourced;
3. compare the behavior with the public contract in `doc/bashlog-spec.md`;
4. reduce the problem to the smallest reproducible logging or redaction call you
   can provide; and
5. note whether standard error is a terminal or redirected, since the default
   `format=auto` behavior depends on that property.

When reporting a problem, useful details include the Bash version, operating
system, bashlog version or commit, selected logging/presentation settings, the
minimal reproduction, expected output, actual standard output, actual standard
error, and any relevant shell options.

Please open non-sensitive support questions and bug reports in the repository
issue tracker:

<https://github.com/wesley-dean/bashlog/issues>

Do not place suspected vulnerabilities, credentials, tokens, private data, or
other sensitive information in a public issue.  Security reports should follow
`SECURITY.md`.
