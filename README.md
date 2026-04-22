# llm_skills

Reusable skill modules for LLM coding agents. Each skill is a self-contained
directory with a `SKILL.md` file — YAML frontmatter + markdown instructions
that can be loaded into an agent's context to give it domain expertise.

## What's a skill?

A skill is a markdown file that teaches an LLM agent how to use a specific
tool, platform, or workflow. Skills are designed to be:

- **Portable** — works with any agent that supports markdown context injection
  (Claude Code skills, custom agents, etc.)
- **Composable** — install only what you need per project or globally
- **Version-controlled** — skills evolve with the tools they describe

## Available skills

| Skill | Description |
|-------|-------------|
| [radicle](radicle/) | Radicle peer-to-peer code forge — issues, patches, sync, clone, identity |

## Install

```bash
# Clone the repo
git clone https://github.com/mikolajmikolajczyk/llm_skills.git

# Install a skill globally (symlink into ~/.claude/skills/)
./llm_skills.sh install radicle --global

# Install into a specific project
./llm_skills.sh install radicle --project ~/src/my-project
```

## Usage

```bash
./llm_skills.sh list                          # List available skills
./llm_skills.sh install <skill> --global      # Install globally
./llm_skills.sh install <skill> --project <p> # Install into project
./llm_skills.sh uninstall <skill> --global    # Remove
./llm_skills.sh search <pattern>              # Search by name/description
```

### Remote skill repos

Fetch skills from other git repositories:

```bash
./llm_skills.sh fetch https://github.com/someone/their-skills.git
./llm_skills.sh install some-skill --global
```

## Skill format

```
my-skill/
└── SKILL.md
```

`SKILL.md` structure:

```yaml
---
name: my-skill
description: One-line description of what this skill covers
user-invocable: false    # auto-loads based on context (optional)
allowed-tools: Bash      # tools the agent can use (optional)
---

# Instructions for the agent

Markdown body with commands, workflows, gotchas, etc.
```

## Contributing

Add a directory with a `SKILL.md`. Keep skills focused — one tool/platform
per skill. Prefer operational reference over tutorials.

## License

[MIT](LICENSE)
