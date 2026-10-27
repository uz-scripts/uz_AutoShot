# Security Policy

## Supported versions

Only the latest release gets security fixes. Update before reporting.

## Reporting a vulnerability

Do not open a public issue for security problems. Report them privately instead:

- [Open a private security advisory](https://github.com/uz-scripts/uz_AutoShot/security/advisories/new) on GitHub, or
- Open a ticket on our [Discord](https://discord.uz-scripts.com) and ask for a staff member.

Include the version, what an attacker can do, and the steps to reproduce it. You will get a reply within a few days. Once a fix is released, we credit you in the release notes unless you prefer otherwise.

## Scope

Things we treat as security issues:

- Sending capture uploads, or changing routing buckets, without the ACE permission while `Customize.AceRestricted = true`
- Writing or overwriting files outside `shots/` through a crafted file name
- A client upload that crashes the server or fills the disk past the size limits in `server/server.js`

Things that are not: problems that need server console or file access, anything a player can do while `Customize.AceRestricted = false` (every player may capture then, by design), and bugs in screenshot-basic, yarn or FiveM itself (report those upstream).
