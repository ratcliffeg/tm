# Security

## Reporting a problem

Please report security problems privately, not in a public issue: on GitHub, go to this
repository's **Security** tab and choose **Report a vulnerability**. Include what you found, how
to reproduce it, and what it lets someone do.

This is a small project looked after in spare time, so there's no fixed response time, but
reports are taken seriously and fixed on `main`.

## What's in scope

tm is a set of bash scripts that run on your own machines, with your own permissions. Things
worth reporting include:

- anything that makes tm run commands or code you didn't ask for (e.g. from a folder or session
  name, a config value, or another machine's output);
- tm exposing secrets, such as a local model server's API key, to other users of the machine;
- unsafe use of shared locations such as `/tmp`.

Out of scope: problems in tmux, fzf, ssh, Claude Code or Codex themselves (report those to their
projects), and anything that needs someone to already be able to run commands as you.

Only the latest `main` is supported.
