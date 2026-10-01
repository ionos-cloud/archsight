---
title: Linux I/O Stack
tags: example, diagram
status: approved
toc: no
---

# Linux I/O Stack

A request from an application passes through the system call interface, the VFS, a filesystem driver, the page
cache, the block layer and a device driver before it reaches the disk.

The diagram is not written in this page. It is the file `linux-fs-stack.asd` next to it, embedded like an image:

```markdown
![Linux kernel I/O stack](linux-fs-stack.asd)
```

![Linux kernel I/O stack](linux-fs-stack.asd)

## Why a separate file

- The same file renders on the command line: `archsight diagram linux-fs-stack.asd -o stack.svg`.
- Several pages can embed one diagram, and a change shows up everywhere.
- `archsight lint` renders it and reports syntax errors with the file name.
- The rendered SVG is also available at `/api/v1/assets/pages/linux-fs-stack.asd`.

See [[Diagrams in Pages]] for the diagram language.
