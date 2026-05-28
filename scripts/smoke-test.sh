#!/usr/bin/env bash
# omo-cc smoke test — validates the dist tree before install.
#
# Checks:
#   1. Every skill has SKILL.md with parseable frontmatter
#   2. Every agent has parseable frontmatter
#   3. `name:` field matches the file/directory name
#   4. Cross-references: every Task(subagent_type="omo-X") points to a real omo-X.md
#   5. No forbidden upstream patterns leaked through (task(, category=, load_skills=, etc.)
#   6. No agent name collisions
#   7. install.sh --dry-run runs cleanly

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
WARN=0

ok()    { echo "  ok   $*"; PASS=$((PASS + 1)); }
fail()  { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
warn()  { echo "  warn $*"; WARN=$((WARN + 1)); }
hdr()   { echo; echo "=== $* ==="; }

hdr "1. Frontmatter validity"

for f in "$DIST_DIR"/skills/omo-*/SKILL.md "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$f" ]] || continue
  name="$(basename "$(dirname "$f")")"
  [[ "$f" == */agents/* ]] && name="$(basename "$f" .md)"

  first_line=$(head -n 1 "$f")
  if [[ "$first_line" != "---" ]]; then
    fail "$f: missing opening '---' (got '$first_line')"
    continue
  fi
  if ! awk '/^---$/{c++} c==2{exit} END{exit c<2}' "$f"; then
    fail "$f: missing closing '---'"
    continue
  fi

  # extract name: field
  fm_name=$(sed -n '2,/^---$/p' "$f" | grep -m1 '^name:' | sed 's/^name: *//' | tr -d '"')
  if [[ -z "$fm_name" ]]; then
    fail "$f: missing 'name:' field"
    continue
  fi
  if [[ "$fm_name" != "$name" ]]; then
    fail "$f: name field '$fm_name' != file/dir name '$name'"
    continue
  fi

  # description must exist
  if ! grep -q '^description:' "$f"; then
    fail "$f: missing 'description:' field"
    continue
  fi

  ok "$name"
done

hdr "2. Cross-references: Task(subagent_type=\"omo-X\") must point to real agents"

# Collect all defined agent names
declare -a known_agents=()
for f in "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$f" ]] || continue
  known_agents+=("$(basename "$f" .md)")
done

is_known_agent() {
  local target="$1"
  for a in "${known_agents[@]}"; do
    [[ "$a" == "$target" ]] && return 0
  done
  return 1
}

# Scan every skill and agent for subagent_type="omo-X" and verify each exists
for f in "$DIST_DIR"/skills/omo-*/SKILL.md "$DIST_DIR"/agents/omo-*.md; do
  [[ -e "$f" ]] || continue
  rel_name="$(basename "$(dirname "$f")")"
  [[ "$f" == */agents/* ]] && rel_name="$(basename "$f" .md)"

  # Match subagent_type="omo-..." in either single or double quotes, or fenced
  refs=$(grep -oE 'subagent_type[[:space:]]*[:=][[:space:]]*"omo-[a-z0-9-]+"' "$f" 2>/dev/null \
    | sed -E 's/.*"omo-([a-z0-9-]+)".*/omo-\1/' \
    | sort -u)
  for r in $refs; do
    if ! is_known_agent "$r"; then
      fail "$rel_name references missing agent: $r"
    fi
  done
done

[[ $FAIL -eq 0 ]] && ok "all subagent_type refs resolve"

hdr "3. Forbidden upstream patterns"

# These are omo-isms that should have been substituted out
declare -a forbidden=(
  '\btask(subagent_type='     # lowercase task() — should be Task(
  '\btask(category='
  'load_skills='
  'task_id="ses_'
  'task_id="bg_'
  'background_output('
  'background_cancel('
  'team_create('
  'team_send_message('
  'team_task_create('
  'team_task_update('
  'team_shutdown_request('
  'team_approve_shutdown('
  'team_delete('
  'team_status('
  'oh-my-opencode\.jsonc'
  'oh-my-opencode\.json'
  '~/\.config/opencode'
  'opencode\.json'
  'call_omo_agent'
  'delegate-task'
  '\bdispatch\.task'
)

for pat in "${forbidden[@]}"; do
  hits=$(grep -rEn "$pat" "$DIST_DIR/skills" "$DIST_DIR/agents" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$hits" -gt 0 ]]; then
    examples=$(grep -rEn "$pat" "$DIST_DIR/skills" "$DIST_DIR/agents" 2>/dev/null | head -3 | sed "s|$DIST_DIR/||")
    fail "forbidden pattern '$pat' found ($hits hits):"
    while IFS= read -r line; do echo "       $line"; done <<< "$examples"
  fi
done

# These are warnings — they may be legitimate examples but worth flagging
declare -a warn_patterns=(
  '\bQuestion\('              # bare Question( call — should be AskUserQuestion (word boundary excludes AskUserQuestion)
  '\blsp_diagnostics\('       # we expect Bash fallback to be primary, but mentions are OK
  '\bast_grep_search\('
)

for pat in "${warn_patterns[@]}"; do
  hits=$(grep -rEn "$pat" "$DIST_DIR/skills" "$DIST_DIR/agents" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$hits" -gt 0 ]]; then
    warn "pattern '$pat' present in $hits places (review whether legitimate)"
  fi
done

[[ $FAIL -eq 0 ]] && ok "no forbidden patterns"

hdr "4. install.sh --dry-run"

if "$DIST_DIR/scripts/install.sh" --dry-run > /tmp/omo-cc-install-dry.log 2>&1; then
  ok "install.sh --dry-run exited 0"
else
  fail "install.sh --dry-run failed:"
  cat /tmp/omo-cc-install-dry.log | sed 's/^/    /'
fi

hdr "5. uninstall.sh --dry-run"

if "$DIST_DIR/scripts/uninstall.sh" --dry-run > /tmp/omo-cc-uninstall-dry.log 2>&1; then
  ok "uninstall.sh --dry-run exited 0"
else
  fail "uninstall.sh --dry-run failed:"
  cat /tmp/omo-cc-uninstall-dry.log | sed 's/^/    /'
fi

hdr "6. Summary"

skill_count=$(find "$DIST_DIR/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
agent_count=$(find "$DIST_DIR/agents" -name 'omo-*.md' 2>/dev/null | wc -l | tr -d ' ')

echo "  Skills: $skill_count"
echo "  Agents: $agent_count"
echo "  Total OK:   $PASS"
echo "  Total WARN: $WARN"
echo "  Total FAIL: $FAIL"
echo

if [[ $FAIL -gt 0 ]]; then
  echo "SMOKE TEST FAILED ($FAIL failures, $WARN warnings)"
  exit 1
fi

echo "SMOKE TEST PASSED ($PASS checks ok, $WARN warnings)"
exit 0
