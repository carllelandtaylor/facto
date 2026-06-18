---
name: ref-skill-writing
description: "Use when writing, reviewing or editing a skill. This skill explains skill types and quality/style guidelines. Reference skill (independent how-tos — use what you need, in any order)."
color: yellow
---

# Writing and reviewing Facto skills

> **Model:** when run as a subagent, prefer `model: opus`.

**This is a reference, not a procedure.** No required order — read the part you need.

---

## Type tag

We add one convention to the standard Claude Code frontmatter: a **type tag** as the last sentence of `description`, declaring the skill's structure. Pick the matching one and copy it character-for-character:

- `Procedure skill (follow the phases in order).` — ordered phases, run start to finish every time.
- `Reference skill (independent how-tos — use what you need, in any order).` — independent how-tos, any order.
- `Procedure + reference skill (run the phases in order once; reuse individual phases as reference when needed).` — both.

---

## Quality and style guidelines

1. **Don't restate details and content from other skills** — when a skill references or calls another, it should never restate any of the referred skill's details or content. We don't want to leak implementation details that could change. Referencing other skills should be like one function calling another: the API is a public contract as to what will be achieved, but how the called function achieves it is hidden. This keeps the skill set maintainable and consistent.
2. **Use plain, direct language** — avoid flowery language and idioms.
3. **When you change an instruction, replace it** — state the new behavior and delete the old one. Editing agents often keep the prior instruction as a prohibition ("…don't do X") where X is just what the skill used to say — but the reader never saw X, so the negation only adds noise. (Warning about a genuine, recurring mistake is different and fine.)
4. **c- skills should look up project-specific information, not bake assumptions into skills** — c-* skills must be reusable across projects, so avoid project-specific assumptions like tools, commands, platforms, etc. For example, a c-* skill that needs to run the real app and take screenshots should inspect the project to see how to do this rather than assuming specific tools.
