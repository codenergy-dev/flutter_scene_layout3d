@AGENTS.md

The line above is an **import, not a link**: it loads
[AGENTS.md](AGENTS.md) into the session itself, rather than trusting an agent
to notice a link and open it. This file used to carry only the link, which
made reading the conventions a choice an agent had to make on its own, every
session, before it could know they existed.

That file is the single source of instructions for coding agents in this
repository: what the packages are, how to run things, the engine rules and the
package traps that are expensive to get wrong, and the conventions for plans,
tests, commit messages and README files.

Put any new agent instruction there rather than in this file. And leave the
first line alone — an import has to be on its own line and outside backticks,
so formatting it as code, indenting it into a list or folding it into the
sentence below silently turns it back into text.
