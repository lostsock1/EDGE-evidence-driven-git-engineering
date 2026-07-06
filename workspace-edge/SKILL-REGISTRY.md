# {{AGENT_NAME}} Skill Registry

Purpose: track reusable {{AGENT_NAME}} skills, especially skills generated from books/documents via `book-to-skill`, and decide which project threads can use them.

## Rules

- {{AGENT_NAME}} core skills stay on the {{AGENT_NAME}} agent and on all {{AGENT_NAME}} project topics unless deliberately restricted.
- Book-derived skills should be added selectively to project topic `skills` allowlists.
- A project topic with a `skills` array only sees that array, so include both core skills and project-specific skills.
- Do not add every book skill globally by default. Add only when useful to a project.

## {{AGENT_NAME}} Core Skills

These are the shared research/tooling skills currently intended for {{AGENT_NAME}}:

| Skill | Purpose |
|---|---|
| `book-to-skill` | Convert books/docs into reusable skills. |
| `hybrid` | Deep web research and source synthesis. |
| `deepeye` | Exhaustive citation-rich research. |
| `smart-scrape` | Adaptive scraping dispatcher. |
| `scrapling-fast` | Fast static/adaptive scraping. |
| `scrapling-adaptive` | Dynamic/stealth/adaptive scraping. |
| `crawlee` | Browser-native crawling and multi-page extraction. |
| `github` | GitHub repository/issues/PR/source research. |
| `gh-issues` | GitHub issue/PR workflow support. |
| `openclaw` | OpenClaw configuration and operations expertise. |

## Generated Book Skills

Add new book-derived skills here after creation.

| Skill | Source book/document | Created | Description | Default projects | Status |
|---|---:|---|---:|---|
<!-- EXAMPLE:
| `the-rag-book` | *The RAG Book* by Author Name | YYYY-MM-DD | Description of what the skill covers | project-slug | ✅ Active |
-->

## API / Infrastructure Skills

| Skill | Source | Created | Description | Default projects | Status |
|---|---:|---|---:|---|
<!-- Add API/infrastructure skills here as they are created. -->

## Project Skill Assignment

| Project | Chat topic | Project manifest | Extra project skills |
|---|---:|---|---|
<!-- EDIT: list your projects here. Delete this comment after populating. -->
<!-- EXAMPLE:
| {{PROJECT_NAME}} | `TOPIC_ID` | `projects/{{PROJECT_SLUG}}/SKILLS.md` | _none yet_ |
-->

## Add-a-book Workflow

1. In an {{AGENT_NAME}} thread, ask {{AGENT_NAME}} to convert the book/document with `book-to-skill`.
2. Choose a stable slug, e.g. `book-empirical-ai-methods`.
3. Store generated skill under a discoverable skill root, preferably `workspace-edge/skills/<slug>/` when supported by the converter.
4. Add the new skill to this registry.
5. Add the new skill to the target project manifest(s), e.g. `projects/{{PROJECT_SLUG}}/SKILLS.md`.
6. Update `~/.openclaw/openclaw.json` topic `skills` allowlist for the relevant chat topic(s).
7. Run `openclaw config validate` and `openclaw skills list --agent edge`.

## Naming Convention

Prefer lowercase, descriptive slugs:

- `book-graph-rag-survey`
- `book-empirical-ai-methods`
- `book-research-design`
- `book-veridical-data-science`
- `book-systems-thinking`
