#!/usr/bin/env bash

set -u

# ============================================================
# Ever Jobs — Test every siteType individually
#
# Tests each provider with:
#   searchTerm: software engineer
#   NO country
#   NO location
#
# Outputs (one folder per run):
#   results/<YYYY-MM-DD_HH-MM-SS>/
#     summary.txt     — table + totals
#     results.csv     — SOURCE, STATUS, COUNT, REASON, JOB_LINKS
#     responses.json  — every source's raw response in one file:
#                       [{ source, status, http_code, count, reason, response }, ...]
#
# Requirements:
#   - Ever Jobs running on localhost:3001
#   - curl
#   - jq
#
# Usage (from anywhere):
#   chmod +x test-all-sources/test-all-sources.sh
#   ./test-all-sources/test-all-sources.sh
#
# Optional:
#   API=http://localhost:3001/api/jobs/search
#   QUERY="senior frontend engineer"
#   RESULTS=10
#   TIMEOUT=90
#   OUT_DIR=/some/other/dir   (default: results/ next to this script)
#
# Example:
#   QUERY="senior frontend engineer" RESULTS=10 ./test-all-sources/test-all-sources.sh
# ============================================================

API="${API:-http://localhost:3001/api/jobs/search}"
QUERY="${QUERY:-software engineer}"
RESULTS="${RESULTS:-5}"
TIMEOUT="${TIMEOUT:-90}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/results}"

SOURCES=(
  linkedin
  indeed
  zip_recruiter
  glassdoor
  google
  bayt
  naukri
  bdjobs
  internshala
  exa
  upwork

  remoteok
  remotive
  jobicy
  himalayas
  arbeitnow
  weworkremotely
  workingnomads
  fourdayweek
  startupjobs
  nodesk
  jobspresso

  usajobs
  adzuna
  reed
  jooble
  careerjet
  careeronestop
  findwork
  jobdataapi

  dice
  simplyhired
  wellfound
  monster
  careerbuilder
  builtin
  snagajob
  dribbble
  themuse
  landingjobs
  echojobs
  jobstreet
  getonboard
  devitjobs
  powertofly
  virtualvocations

  hackernews
  jobsacuk
  jobindex
  mycareersfuture
  jobsinjapan
  jobsch
  duunitori
  guardianjobs
  jobsdb
  headhunter
  djinni

  authenticjobs
  cryptojobslist
  higheredjobs
  fossjobs
  larajobs
  pythonjobs
  drupaljobs
  golangjobs
  wordpressjobs
  vuejobs
  railsjobs
  elixirjobs
  androidjobs
  iosdevjobs
  devopsjobs
  clojurejobs
  functionalworks
  realworkfromanywhere
  conservationjobs
  coroflot
  crunchboard
  icrunchdata
  swissdevjobs
  berlinstartupjobs
  nofluffjobs
  greenjobsboard
  eurojobs
  opensourcedesignjobs
  academiccareers
  remotefirstjobs
  techcareers
  hasjob
  habrcareer
  joinrise

  talroo
  infojobs
  jobtechdev
  francetravail
  navjobs
  arbeitsagentur
  canadajobbank
  reliefweb
  undpjobs
)

# Remove duplicate source IDs while preserving order.
# (Portable to macOS's bash 3.2, which has no `mapfile`.)
DEDUPED=()
while IFS= read -r LINE; do
  DEDUPED+=("$LINE")
done < <(printf '%s\n' "${SOURCES[@]}" | awk '!seen[$0]++')
SOURCES=("${DEDUPED[@]}")

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required."
  echo "macOS: brew install jq"
  echo "Ubuntu/Debian: sudo apt install jq"
  exit 1
fi

RUN_DIR="$OUT_DIR/$(date '+%Y-%m-%d_%H-%M-%S')"
RESULT_FILE="$RUN_DIR/summary.txt"
CSV_FILE="$RUN_DIR/results.csv"
JSON_FILE="$RUN_DIR/responses.json"
# One JSON object per line, appended as each source finishes, so partial
# results survive a Ctrl-C. Folded into $JSON_FILE at the end of the run.
JSONL_FILE="$RUN_DIR/.responses.jsonl"
RESPONSE_FILE="$RUN_DIR/.response.tmp"

mkdir -p "$RUN_DIR"
: > "$JSONL_FILE"

TOTAL="${#SOURCES[@]}"

echo
echo "=============================================================="
echo " Ever Jobs — Source Test"
echo "=============================================================="
echo "API:       $API"
echo "Query:     $QUERY"
echo "Results:   $RESULTS"
echo "Location:  NOT SET"
echo "Country:   NOT SET"
echo "Sources:   $TOTAL"
echo "Timeout:   ${TIMEOUT}s per source"
echo "Output:    $RUN_DIR"
echo "=============================================================="
echo

# TXT header
{
  echo "Ever Jobs Source Test"
  echo "Date: $(date)"
  echo "API: $API"
  echo "Query: $QUERY"
  echo "Results: $RESULTS"
  echo "Location: NOT SET"
  echo "Country: NOT SET"
  echo
  printf "%-28s %-14s %-8s %s\n" \
    "SOURCE" "STATUS" "COUNT" "REASON"
  printf "%-28s %-14s %-8s %s\n" \
    "----------------------------" \
    "--------------" \
    "--------" \
    "------------------------------"
} > "$RESULT_FILE"

# CSV header
printf '%s\n' 'SOURCE,STATUS,COUNT,REASON,JOB_LINKS' > "$CSV_FILE"

printf "%-28s %-14s %-8s %s\n" \
  "SOURCE" "STATUS" "COUNT" "REASON"

printf "%-28s %-14s %-8s %s\n" \
  "----------------------------" \
  "--------------" \
  "--------" \
  "------------------------------"

WORKING=0
BLOCKED=0
AUTH=0
ERRORS=0
EMPTY=0

for SOURCE in "${SOURCES[@]}"; do

  echo "Testing $SOURCE..." >&2

  REQUEST_BODY="$(
    jq -n \
      --arg query "$QUERY" \
      --arg source "$SOURCE" \
      --argjson results "$RESULTS" \
      '{
        searchTerm: $query,
        siteType: [$source],
        resultsWanted: $results,
        descriptionFormat: "plain"
      }'
  )"

  : > "$RESPONSE_FILE"

  HTTP_CODE="$(
    curl -sS \
      --max-time "$TIMEOUT" \
      -o "$RESPONSE_FILE" \
      -w "%{http_code}" \
      -X POST "$API" \
      -H "Content-Type: application/json" \
      -d "$REQUEST_BODY" \
      2>/dev/null
  )"

  STATUS="ERROR"
  COUNT="-"
  REASON="request failed/timeout"
  JOB_LINKS='[]'

  if [ "$HTTP_CODE" = "000" ]; then
    STATUS="ERROR"
    ERRORS=$((ERRORS + 1))

  elif ! jq -e . "$RESPONSE_FILE" >/dev/null 2>&1; then
    STATUS="ERROR"
    REASON="invalid JSON (HTTP $HTTP_CODE)"
    ERRORS=$((ERRORS + 1))

  else

    COUNT="$(jq -r '.count // 0' "$RESPONSE_FILE" 2>/dev/null || echo 0)"

    # --------------------------------------------------------
    # Extract job URLs robustly.
    #
    # Ever Jobs/source versions can expose different URL field
    # names, so check the common variants.
    # --------------------------------------------------------
    JOB_LINKS="$(
      jq -c '
        [
          (.jobs // [])[]
          |
          (
            .jobUrl
            // .job_url
            // .url
            // .jobApplyLink
            // .job_apply_link
            // .applyUrl
            // .apply_url
            // .link
            // empty
          )
        ]
        | map(select(type == "string" and length > 0))
        | unique
      ' "$RESPONSE_FILE" 2>/dev/null
    )"

    if [ -z "$JOB_LINKS" ]; then
      JOB_LINKS='[]'
    fi

    REASON="$(
      jq -r '
        (.per_source_summary.by_reason // {})
        | to_entries
        | map("\(.key)=\(.value)")
        | join(", ")
      ' "$RESPONSE_FILE" 2>/dev/null
    )"

    if [ -z "$REASON" ]; then
      REASON="$(
        jq -r '
          (.per_source // [])
          | map(
              [
                (.reason // empty),
                (.status // empty),
                (.error // empty)
              ]
              | map(select(. != ""))
              | join(":")
            )
          | map(select(. != ""))
          | join(", ")
        ' "$RESPONSE_FILE" 2>/dev/null
      )"
    fi

    BLOCKED_COUNT="$(
      jq -r '.per_source_summary.by_reason.blocked // 0' \
        "$RESPONSE_FILE" 2>/dev/null
    )"

    AUTH_COUNT="$(
      jq -r '
        (
          (.per_source_summary.by_reason.auth_required // 0)
          + (.per_source_summary.by_reason.authentication_required // 0)
          + (.per_source_summary.by_reason.unauthorized // 0)
        )
      ' "$RESPONSE_FILE" 2>/dev/null
    )"

    ERROR_COUNT="$(
      jq -r '
        (
          (.per_source_summary.by_reason.error // 0)
          + (.per_source_summary.by_reason.failed // 0)
        )
      ' "$RESPONSE_FILE" 2>/dev/null
    )"

    if [ "$COUNT" -gt 0 ] 2>/dev/null; then
      STATUS="WORKING"
      WORKING=$((WORKING + 1))

    elif [ "${BLOCKED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
      STATUS="BLOCKED"
      BLOCKED=$((BLOCKED + 1))

    elif [ "${AUTH_COUNT:-0}" -gt 0 ] 2>/dev/null; then
      STATUS="AUTH"
      AUTH=$((AUTH + 1))

    elif [ "${ERROR_COUNT:-0}" -gt 0 ] 2>/dev/null; then
      STATUS="ERROR"
      ERRORS=$((ERRORS + 1))

    else
      STATUS="EMPTY"
      EMPTY=$((EMPTY + 1))

      if [ -z "$REASON" ]; then
        REASON="0 results / inconclusive"
      fi
    fi

    if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
      if [ "$STATUS" = "EMPTY" ]; then
        STATUS="ERROR"
        EMPTY=$((EMPTY - 1))
        ERRORS=$((ERRORS + 1))
      fi

      if [ -z "$REASON" ]; then
        REASON="HTTP $HTTP_CODE"
      else
        REASON="HTTP $HTTP_CODE; $REASON"
      fi
    fi
  fi

  if [ -z "$REASON" ]; then
    REASON="none"
  fi

  # Keep terminal output readable.
  DISPLAY_REASON="$REASON"
  if [ ${#DISPLAY_REASON} -gt 70 ]; then
    DISPLAY_REASON="${DISPLAY_REASON:0:67}..."
  fi

  printf "%-28s %-14s %-8s %s\n" \
    "$SOURCE" "$STATUS" "$COUNT" "$DISPLAY_REASON"

  printf "%-28s %-14s %-8s %s\n" \
    "$SOURCE" "$STATUS" "$COUNT" "$DISPLAY_REASON" >> "$RESULT_FILE"

  # ----------------------------------------------------------
  # CSV row
  #
  # JOB_LINKS is stored as a JSON array:
  # ["https://...", "https://..."]
  #
  # jq @csv handles commas, quotes and JSON safely.
  # ----------------------------------------------------------
  jq -nr \
    --arg source "$SOURCE" \
    --arg status "$STATUS" \
    --arg count "$COUNT" \
    --arg reason "$REASON" \
    --arg job_links "$JOB_LINKS" \
    '[$source, $status, $count, $reason, $job_links] | @csv' \
    >> "$CSV_FILE"

  # ----------------------------------------------------------
  # Accumulate the raw response. Valid JSON is embedded as-is;
  # anything else (HTML error page, empty body) is kept as a string.
  # ----------------------------------------------------------
  if jq -e . "$RESPONSE_FILE" >/dev/null 2>&1; then
    RESPONSE_ARGS=(--slurpfile body "$RESPONSE_FILE")
    RESPONSE_EXPR='$body[0]'
  else
    RESPONSE_ARGS=(--rawfile body "$RESPONSE_FILE")
    RESPONSE_EXPR='$body'
  fi

  jq -nc \
    --arg source "$SOURCE" \
    --arg status "$STATUS" \
    --arg http_code "$HTTP_CODE" \
    --arg count "$COUNT" \
    --arg reason "$REASON" \
    "${RESPONSE_ARGS[@]}" \
    "{
      source: \$source,
      status: \$status,
      http_code: (\$http_code | tonumber? // \$http_code),
      count: (\$count | tonumber? // null),
      reason: \$reason,
      response: $RESPONSE_EXPR
    }" >> "$JSONL_FILE"

done

jq -s . "$JSONL_FILE" > "$JSON_FILE" && rm -f "$JSONL_FILE"
rm -f "$RESPONSE_FILE"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "=============================================================="
echo " Summary"
echo "=============================================================="
echo "Total:    $TOTAL"
echo "Working:  $WORKING"
echo "Blocked:  $BLOCKED"
echo "Auth:     $AUTH"
echo "Errors:   $ERRORS"
echo "Empty:    $EMPTY"
echo "=============================================================="
echo
echo "TXT:"
echo "  $RESULT_FILE"
echo
echo "CSV:"
echo "  $CSV_FILE"
echo
echo "Responses:"
echo "  $JSON_FILE"
echo

{
  echo
  echo "=============================================================="
  echo "Summary"
  echo "=============================================================="
  echo "Total:    $TOTAL"
  echo "Working:  $WORKING"
  echo "Blocked:  $BLOCKED"
  echo "Auth:     $AUTH"
  echo "Errors:   $ERRORS"
  echo "Empty:    $EMPTY"
} >> "$RESULT_FILE"
