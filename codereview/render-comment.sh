#!/usr/bin/env bash
#
# Copyright (C) 2026 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# Renders the AI code review result into the PR comment markdown, on stdout.
# Usage: render-comment.sh <review-result.json>
# The review text is model output, so it is untrusted: mentions are neutralised,
# HTML comments are escaped (the sticky-comment marker cannot be forged) and size is capped.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <review-result.json>" >&2
  exit 2
fi

jq -r --arg marker '<!-- ai-code-review -->' '
  def sanitize:
    gsub("@(?<c>[A-Za-z0-9])"; "@​\(.c)")
    | gsub("<!--"; "&lt;!--")
    | if length > 60000 then .[0:60000] + "\n\n…(truncated)" else . end;
  def usd: (. * 100 | round) as $c | "$\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)";

  (if .usage then (.usage.cost_usd | usd) else "n/a" end) as $cost
  | (if .failed then "⚠️ Review failed or timed out"
     elif .status == "ACCEPT" then "✅ Approved"
     elif .status == "ACCEPT_WITH_NITS" then "🟡 Approved with nits"
     else "❌ Changes requested" end) as $title
  | [
      $marker,
      "### AI code review: \($title) for commit `\(.head_sha[0:7])`",
      "",
      (.comments | tostring | sanitize),
      "",
      "---",
      "<sub>Model `\(.model)` · \(.duration_s)s · estimated cost \($cost)"
        + (if .usage then " · tokens in \(.usage.input_tokens) / out \(.usage.output_tokens) (\(.usage.num_turns) turns)" else "" end)
        + " · [Run details](\(.run_url)). AI review is advisory: a maintainer still has to review and approve this PR.</sub>"
    ] | join("\n")
' "$1"
