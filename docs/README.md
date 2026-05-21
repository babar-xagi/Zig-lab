# Zig-lab Documentation

This folder contains the planning documents for Zig-lab before application code begins.

## Documents

- [../EXAMPLE.md](../EXAMPLE.md): preview examples showing the intended app, notebook, CLI, and output experience.
- [ROADMAP.md](ROADMAP.md): project phases, milestones, and acceptance criteria.
- [FEATURES.md](FEATURES.md): product feature map and unique ideas.
- [ARCHITECTURE.md](ARCHITECTURE.md): proposed architecture and module boundaries.
- [JUPYTER_KERNEL_STRATEGY.md](JUPYTER_KERNEL_STRATEGY.md): plan for a Jupyter/Anaconda Zig kernel and comparison with a native editor.

## Planning Principles

- Start with the execution model before building a large editor.
- Keep notebooks text-friendly and version-control friendly.
- Use real Zig tooling wherever possible.
- Make every rich feature earn its place through a developer workflow.
- Prefer a small working vertical slice over a broad unfinished shell.

## MVP Question

The first prototype should answer one question:

Can Zig-lab run a Zig cell, show useful output and diagnostics, preserve notebook state, and rerun reliably?

If the answer is yes, the editor can grow around that foundation.
