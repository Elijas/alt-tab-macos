# Historical AltTab fork notes

These six documents were moved from the unversioned parent `_forks` directory
into this repository on 2026-10-27. They preserve earlier development decisions,
debugging methods, and observations from the personal AltTab fork.

The documents describe earlier source layouts, worktrees, logging behavior, and
local builds. Treat their commands and technical claims as historical context.
For current development instructions, use the repository's [AGENTS.md](../../../AGENTS.md)
and [README](../../../README.md). The current checkout uses `dev`.

- [Historical parent instructions](historical-parent-instructions.md): the former
  parent `CLAUDE.md`, including build notes, crash investigations, and CLI design.
  Its filename deliberately prevents it from becoming active agent instructions.
- [Upstream v10.9 merge notes](docs/post-merge-upstream-v10.9.md)
- [Window debugging guide](docs/window-debugging-guide.md)
- [Native tab hierarchy guide](docs/tab-hierarchy-guide.md)
- [Group sorting guide](docs/group-sort-guide.md)
- [Gesture and keyboard tab-filter diagnosis](docs/gesture-tab-filter-fix.md)

The original prose and examples are preserved. One relative link in the former
parent instructions was updated to reach the existing
[v10.11 merge notes](../../post-merge-upstream-v10.11.md). References in the older
guides to `CLAUDE.md` mean the historical parent instructions above.
