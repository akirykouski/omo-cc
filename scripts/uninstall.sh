#!/usr/bin/env bash
# omo-cc uninstaller — removes only omo-* skills and agents from ~/.claude.
# Never touches anything without the omo- prefix.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
BACKUP_DIR="${CLAUDE_DIR}/backups/omo-cc-uninstall-${TIMESTAMP}"

DRY_RUN=0
VERBOSE=0
KEEP_BACKUPS=1   # default: back up before removing

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--dry-run] [--no-backup] [--verbose] [--help]

Remove omo-cc skills and agents from ~/.claude (or $CLAUDE_HOME).

Only touches files matching:
  ~/.claude/skills/omo-*
  ~/.claude/agents/omo-*.md

By default, removed files are backed up to ~/.claude/backups/omo-cc-uninstall-<timestamp>/
Use --no-backup to skip the backup.

Options:
  --dry-run     Print actions, do not remove anything.
  --no-backup   Don't back up removed files (default: keep backups).
  --verbose     Print each file as it's processed.
  --help        Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-backup) KEEP_BACKUPS=0 ;;
    --verbose) VERBOSE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

log() { echo "[omo-cc uninstall] $*"; }
vlog() { [[ $VERBOSE -eq 1 ]] && echo "  $*" || true; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

log "Target: $CLAUDE_DIR"
[[ $DRY_RUN -eq 1 ]] && log "Mode: DRY RUN (no changes will be made)"
[[ $KEEP_BACKUPS -eq 1 ]] && log "Backups will be written to: $BACKUP_DIR"
[[ $KEEP_BACKUPS -eq 0 ]] && log "No backups (--no-backup)"

SKILLS_REMOVED=0
AGENTS_REMOVED=0

# Skills under ~/.claude/skills/omo-*
if [[ -d "$CLAUDE_DIR/skills" ]]; then
  for d in "$CLAUDE_DIR"/skills/omo-*; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    # Hard safety: must start with omo-
    if [[ "$name" != omo-* ]]; then
      echo "SAFETY: $d does not start with 'omo-', skipping" >&2
      continue
    fi
    if [[ $KEEP_BACKUPS -eq 1 ]]; then
      run "mkdir -p '$BACKUP_DIR/skills'"
      run "cp -R '$d' '$BACKUP_DIR/skills/$name'"
    fi
    run "rm -rf '$d'"
    SKILLS_REMOVED=$((SKILLS_REMOVED + 1))
    vlog "removed skill: $name"
  done
fi

# Agents under ~/.claude/agents/omo-*.md
if [[ -d "$CLAUDE_DIR/agents" ]]; then
  for f in "$CLAUDE_DIR"/agents/omo-*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    if [[ "$name" != omo-* ]]; then
      echo "SAFETY: $f does not start with 'omo-', skipping" >&2
      continue
    fi
    if [[ $KEEP_BACKUPS -eq 1 ]]; then
      run "mkdir -p '$BACKUP_DIR/agents'"
      run "cp '$f' '$BACKUP_DIR/agents/$name'"
    fi
    run "rm -f '$f'"
    AGENTS_REMOVED=$((AGENTS_REMOVED + 1))
    vlog "removed agent: $name"
  done
fi

log "---"
log "Removed $SKILLS_REMOVED skills, $AGENTS_REMOVED agents."
if [[ $KEEP_BACKUPS -eq 1 ]] && [[ $((SKILLS_REMOVED + AGENTS_REMOVED)) -gt 0 ]]; then
  log "Backup: $BACKUP_DIR"
fi
log "Done."
[[ $DRY_RUN -eq 1 ]] && log "(dry-run — no actual changes made)"
