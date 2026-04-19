#!/usr/bin/env bash
# Seed the Composer ingest API with sample items for manual testing.
#
# Usage:
#   ./scripts/seed_fixtures.sh                 # uses default port 5006
#   COMPOSER_URL=http://... ./scripts/seed_fixtures.sh
#   COMPOSER_INGEST_KEY=... ./scripts/seed_fixtures.sh   # if auth enabled
#
# Posts 5 fake "promoted from DataPoints" items. Safe to re-run — the
# ingest endpoint is idempotent on (source, source_ref).

set -euo pipefail

URL="${COMPOSER_URL:-http://127.0.0.1:5006}"
HEADER=""
if [[ -n "${COMPOSER_INGEST_KEY:-}" ]]; then
  HEADER="-H X-Ingest-Key:${COMPOSER_INGEST_KEY}"
fi

post() {
  local ref="$1"
  local title="$2"
  local author="$3"
  local url="$4"
  local summary="$5"
  local content="$6"
  local keywords_json="$7"

  # shellcheck disable=SC2086
  curl -sS -X POST "$URL/v1/ingest/items" \
    -H "Content-Type: application/json" \
    $HEADER \
    -d "$(cat <<JSON
{
  "source": "datapoints",
  "source_ref": "$ref",
  "url": "$url",
  "title": "$title",
  "author": "$author",
  "published_at": "2026-04-17T10:00:00Z",
  "summary": "$summary",
  "content": "$content",
  "key_points": ["First point about the topic", "Second observation", "Third implication"],
  "keywords": $keywords_json,
  "related_links": [{"url": "https://example.com/related", "title": "Related read", "score": 0.82}],
  "metadata": {"site": "example.com"}
}
JSON
)"
  echo
}

post "dp-001" \
  "Fed holds rates steady, signals two cuts by year-end" \
  "Jane Reporter" \
  "https://example.com/fed-rates-2026" \
  "The Federal Reserve held rates at 4.5 percent and signaled two cuts by December." \
  "The Federal Open Market Committee concluded its April meeting with rates unchanged at 4.5 percent. Chair Powell indicated that two rate cuts are likely before year-end, contingent on continued moderation in core inflation..." \
  '["federal-reserve", "interest-rates", "monetary-policy"]'

post "dp-002" \
  "OpenAI ships agentic developer SDK" \
  "Tech Staff" \
  "https://example.com/openai-agents" \
  "OpenAI released a developer SDK for building multi-step autonomous agents, with built-in tool use and memory." \
  "OpenAI today announced a new SDK for building agentic applications. The package includes primitives for tool use, long-running memory, and sub-agent delegation. Early adopters report..." \
  '["openai", "agents", "developer-tools", "sdk"]'

post "dp-003" \
  "Supreme Court takes up second AI copyright case" \
  "Legal Affairs Desk" \
  "https://example.com/scotus-ai-copyright" \
  "The court granted certiorari on a case examining whether training a model on copyrighted work is transformative use." \
  "The Supreme Court today granted certiorari in Publishers v. DataCorp, the second major AI copyright case to reach the Court in the past year..." \
  '["supreme-court", "copyright", "ai-policy"]'

post "dp-004" \
  "Why your build system is slow" \
  "Dev Practitioner" \
  "https://example.com/build-system-slow" \
  "A long essay arguing that most build system slowness comes from cache invalidation strategy, not raw compute." \
  "Most engineering teams blame their hardware when builds slow down. The real culprit is almost always the caching layer..." \
  '["build-systems", "performance", "engineering"]'

post "dp-005" \
  "New climate data shows warming trend accelerating" \
  "Science Writer" \
  "https://example.com/climate-2026" \
  "April data from NOAA shows the twelve-month warming trend exceeded 1.6°C above pre-industrial baseline." \
  "NOAA's April data release marked the twelfth consecutive month of record-setting global temperatures. The twelve-month rolling average..." \
  '["climate", "science", "noaa"]'

echo "Done. List them with: curl $URL/items | jq ."
