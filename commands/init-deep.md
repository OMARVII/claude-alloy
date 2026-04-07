---
description: "Generate hierarchical CLAUDE.md files throughout the project for optimal agent context."
---

# Init Deep — Hierarchical Context Generation

Generate CLAUDE.md files throughout the project directory tree. Each file provides context specific to its directory.

## Process:

1. **Scan project structure**: Read the directory tree to understand the architecture
2. **Identify key directories**: src/, lib/, components/, api/, routes/, services/, utils/, tests/, etc.
3. **For each key directory**, create a CLAUDE.md that describes:
   - Purpose of this directory
   - Key files and their roles
   - Patterns and conventions used here
   - Dependencies and relationships to other directories
   - Common operations (how to add new files, run tests, etc.)

4. **Root CLAUDE.md** should contain:
   - Project overview and architecture
   - Tech stack and key dependencies
   - Build, test, and deploy commands
   - Coding conventions and style guide
   - Common patterns used across the project

## Rules:
- Keep each CLAUDE.md concise (under 100 lines)
- Focus on what an AI agent needs to know to work in that directory
- Reference specific files by name when relevant
- Include code patterns with brief examples
- Do NOT duplicate information between parent and child CLAUDE.md files
- Skip directories that don't benefit from context (node_modules, .git, dist, build)

## Output Structure:
```
project/
├── CLAUDE.md              ← Project-wide context
├── src/
│   ├── CLAUDE.md          ← src-specific patterns
│   ├── components/
│   │   └── CLAUDE.md      ← component conventions
│   ├── api/
│   │   └── CLAUDE.md      ← API patterns
│   └── utils/
│       └── CLAUDE.md      ← utility patterns
└── tests/
    └── CLAUDE.md          ← testing conventions
```

Begin scanning the project now.
