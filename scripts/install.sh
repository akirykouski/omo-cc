#!/usr/bin/env bash
# omo-cc installer — copies skills, agents, and commands into ~/.claude
# Idempotent. Supports --dry-run. Backs up any existing omo-* before overwriting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
BACKUP_DIR="${CLAUDE_DIR}/backups/omo-cc-${TIMESTAMP}"

DRY_RUN=0
VERBOSE=0

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run] [--verbose] [--help]

Install omo-cc skills and agents into ~/.claude (or $CLAUDE_HOME).

Options:
  --dry-run     Print actions, do not copy anything.
  --verbose     Print each file as it's processed.
  --help        Show this help.

Files installed (in ~/.claude/):
  skills/omo-*/SKILL.md
  agents/omo-*.md

Existing files with the same names are backed up to:
  ~/.claude/backups/omo-cc-<timestamp>/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --verbose) VERBOSE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

log() { echo "[omo-cc install] $*"; }
vlog() { [[ $VERBOSE -eq 1 ]] && echo "  $*" || true; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# Lightweight frontmatter sanity check — every skill/agent must start with `---`
# and have a closing `---` plus a `name:` field.
validate_frontmatter() {
  local f="$1"
  local first_line
  first_line=$(head -n 1 "$f")
  if [[ "$first_line" != "---" ]]; then
    echo "FAIL: $f does not start with '---' (got '$first_line')" >&2
    return 1
  fi
  if ! awk '/^---$/{c++} c==2{exit} END{exit c<2}' "$f"; then
    echo "FAIL: $f missing closing '---' for frontmatter" >&2
    return 1
  fi
  if ! grep -q '^name:' "$f"; then
    echo "FAIL: $f missing 'name:' in frontmatter" >&2
    return 1
  fi
  return 0
}

log "Source: $DIST_DIR"
log "Target: $CLAUDE_DIR"
[[ $DRY_RUN -eq 1 ]] && log "Mode: DRY RUN (no changes will be made)"

if [[ ! -d "$DIST_DIR/skills" ]] || [[ ! -d "$DIST_DIR/agents" ]]; then
  echo "ERROR: expected $DIST_DIR/skills and $DIST_DIR/agents to exist" >&2
  exit 1
fi

# Validate all source files before touching anything
log "Validating source frontmatter..."
INVALID=0
for f in "$DIST_DIR"/skills/omo-*/SKILL.md "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$f" ]] || continue
  if validate_frontmatter "$f"; then
    vlog "ok: $f"
  else
    INVALID=$((INVALID + 1))
  fi
done

if [[ $INVALID -gt 0 ]]; then
  echo "ERROR: $INVALID files failed validation. Aborting." >&2
  exit 1
fi

# Ensure target dirs exist
run "mkdir -p '$CLAUDE_DIR/skills' '$CLAUDE_DIR/agents'"

SKILLS_INSTALLED=0
AGENTS_INSTALLED=0
BACKED_UP=0
HAS_BACKUPS=0

# Backup any existing omo-* before overwriting
for src in "$DIST_DIR"/skills/omo-*/SKILL.md; do
  [[ -e "$src" ]] || continue
  skill_dir="$(basename "$(dirname "$src")")"
  target="$CLAUDE_DIR/skills/$skill_dir"
  if [[ -d "$target" ]]; then
    [[ $HAS_BACKUPS -eq 0 ]] && { run "mkdir -p '$BACKUP_DIR/skills'"; HAS_BACKUPS=1; }
    run "cp -R '$target' '$BACKUP_DIR/skills/$skill_dir'"
    BACKED_UP=$((BACKED_UP + 1))
    vlog "backed up skill: $skill_dir"
  fi
done

for src in "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$src" ]] || continue
  agent_file="$(basename "$src")"
  target="$CLAUDE_DIR/agents/$agent_file"
  if [[ -f "$target" ]]; then
    [[ $HAS_BACKUPS -eq 0 ]] && { run "mkdir -p '$BACKUP_DIR/agents'"; HAS_BACKUPS=1; }
    [[ ! -d "$BACKUP_DIR/agents" ]] && run "mkdir -p '$BACKUP_DIR/agents'"
    run "cp '$target' '$BACKUP_DIR/agents/$agent_file'"
    BACKED_UP=$((BACKED_UP + 1))
    vlog "backed up agent: $agent_file"
  fi
done

# Copy skills
for src in "$DIST_DIR"/skills/omo-*/SKILL.md; do
  [[ -e "$src" ]] || continue
  skill_dir="$(basename "$(dirname "$src")")"
  target_dir="$CLAUDE_DIR/skills/$skill_dir"
  run "mkdir -p '$target_dir'"
  run "cp '$src' '$target_dir/SKILL.md'"
  SKILLS_INSTALLED=$((SKILLS_INSTALLED + 1))
  vlog "installed skill: $skill_dir"
done

# Copy agents
for src in "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$src" ]] || continue
  agent_file="$(basename "$src")"
  run "cp '$src' '$CLAUDE_DIR/agents/$agent_file'"
  AGENTS_INSTALLED=$((AGENTS_INSTALLED + 1))
  vlog "installed agent: $agent_file"
done

log "---"
log "Installed $SKILLS_INSTALLED skills, $AGENTS_INSTALLED agents."
if [[ $BACKED_UP -gt 0 ]]; then
  log "Backed up $BACKED_UP existing file(s) to: $BACKUP_DIR"
fi
log "Done."
[[ $DRY_RUN -eq 1 ]] && log "(dry-run — no actual changes made)"
