#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="/opt/logicasimatematica-site"
BOOT="/var/lib/cccc-seo/lm-ga4/bootstrap-v1"
RUN_ROOT="/var/lib/cccc-seo/lm-ga4/runs"
RUN_ID="LM-GA4-CONSENT-V1-20260817"
RUN_DIR="$RUN_ROOT/$RUN_ID"
STATUS_FILE="$RUN_DIR/status.env"
SUMMARY_FILE="$RUN_DIR/summary.json"
LOCK_FILE="/var/lock/lm-ga4-consent-v1.lock"
MEASUREMENT_ID="G-4C4JFDT4F2"
PROPERTY_ID="550144249"
STREAM_ID="15449971346"

mkdir -p "$RUN_DIR"
chmod 700 "$RUN_ROOT" "$RUN_DIR" 2>/dev/null || true
exec 9>"$LOCK_FILE"
flock -n 9 || {
  printf 'STATUS=BLOCKED\nREASON=LOCK_HELD\n' > "$STATUS_FILE"
  exit 75
}

ACTIVE_BEFORE="$(readlink -f "$ROOT/dist_current")"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$ROOT/backups/lm-ga4-consent-$STAMP"
SOURCE_BUILD="$RUN_DIR/source-build"
NEW_RELEASE="$ROOT/releases/release_LM-GA4-CONSENT-V1_${STAMP}"
LOCAL_PORT=18765
SERVER_PID=""
DEPLOY_SWITCHED=0
SOURCE_PATCHED=0

status() {
  {
    printf 'STATUS=%s\n' "$1"
    printf 'STEP=%s\n' "$2"
    printf 'UPDATED_AT=%s\n' "$(date -u +%FT%TZ)"
    printf 'ACTIVE_BEFORE=%s\n' "$ACTIVE_BEFORE"
    printf 'NEW_RELEASE=%s\n' "$NEW_RELEASE"
  } > "$STATUS_FILE"
}

restore_source() {
  [[ -d "$BACKUP_DIR/source" ]] || return 0
  if [[ -f "$BACKUP_DIR/source/Layout.astro" ]]; then
    cp -a "$BACKUP_DIR/source/Layout.astro" "$ROOT/src/layouts/Layout.astro"
  fi
  if [[ -f "$BACKUP_DIR/source/AnalyticsConsent.astro" ]]; then
    cp -a "$BACKUP_DIR/source/AnalyticsConsent.astro" "$ROOT/src/components/AnalyticsConsent.astro"
  else
    rm -f "$ROOT/src/components/AnalyticsConsent.astro"
  fi
  if [[ -f "$BACKUP_DIR/source/politica-de-confidentialitate.astro" ]]; then
    cp -a "$BACKUP_DIR/source/politica-de-confidentialitate.astro" "$ROOT/src/pages/politica-de-confidentialitate.astro"
  else
    rm -f "$ROOT/src/pages/politica-de-confidentialitate.astro"
  fi
}

rollback_live() {
  [[ "$DEPLOY_SWITCHED" -eq 1 ]] || return 0
  local tmp="$ROOT/.dist_current.rollback.$$"
  rm -f "$tmp"
  ln -s "$ACTIVE_BEFORE" "$tmp"
  mv -Tf "$tmp" "$ROOT/dist_current"
  DEPLOY_SWITCHED=0
}

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

on_error() {
  local rc=$?
  set +e
  rollback_live
  if [[ "$SOURCE_PATCHED" -eq 1 ]]; then restore_source; fi
  status "FAIL" "ROLLBACK_COMPLETE"
  {
    printf 'FAILED_AT=%s\n' "$(date -u +%FT%TZ)"
    printf 'EXIT_CODE=%s\n' "$rc"
    printf 'LIVE_ROLLBACK=PASS\n'
    printf 'SOURCE_ROLLBACK=PASS\n'
  } >> "$STATUS_FILE"
  exit "$rc"
}
trap on_error ERR

status "RUNNING" "PREFLIGHT"

[[ -d "$ROOT/src/layouts" ]]
[[ -f "$ROOT/src/layouts/Layout.astro" ]]
[[ -d "$ACTIVE_BEFORE" ]]
[[ "$ACTIVE_BEFORE" == "$ROOT"/releases/* ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 'https://logicasimatematica.ro/?lm-ga4-preflight=1')" == "200" ]]
! grep -RIl --include='*.html' -E '\bG-[A-Z0-9]{6,}\b|\bGTM-[A-Z0-9]{4,}\b|googletagmanager\.com' "$ACTIVE_BEFORE" | grep -q .

mkdir -p "$BACKUP_DIR/source"
cp -a "$ROOT/src/layouts/Layout.astro" "$BACKUP_DIR/source/Layout.astro"
[[ ! -f "$ROOT/src/components/AnalyticsConsent.astro" ]] || cp -a "$ROOT/src/components/AnalyticsConsent.astro" "$BACKUP_DIR/source/AnalyticsConsent.astro"
[[ ! -f "$ROOT/src/pages/politica-de-confidentialitate.astro" ]] || cp -a "$ROOT/src/pages/politica-de-confidentialitate.astro" "$BACKUP_DIR/source/politica-de-confidentialitate.astro"
printf '%s\n' "$ACTIVE_BEFORE" > "$BACKUP_DIR/dist_current.target"
find "$ACTIVE_BEFORE" -type f -print0 | sort -z | xargs -0 sha256sum > "$BACKUP_DIR/active-release.sha256"
sha256sum "$BOOT/AnalyticsConsent.astro" "$BOOT/politica-de-confidentialitate.astro" "$BOOT/static-head.html" "$BOOT/static-body.html" > "$BACKUP_DIR/payload.sha256"

status "RUNNING" "PATCH_SOURCE"

install -m 0644 "$BOOT/AnalyticsConsent.astro" "$ROOT/src/components/AnalyticsConsent.astro"
install -m 0644 "$BOOT/politica-de-confidentialitate.astro" "$ROOT/src/pages/politica-de-confidentialitate.astro"
python3 - "$ROOT/src/layouts/Layout.astro" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

import_line = 'import AnalyticsConsent from "../components/AnalyticsConsent.astro";'
if import_line not in text:
    marker = 'import "../styles/editorial.css";'
    if text.count(marker) != 1:
        raise SystemExit("layout import marker mismatch")
    text = text.replace(marker, marker + "\n" + import_line, 1)

privacy_link = '<a href="/politica-de-confidentialitate/" style="color: var(--primary-color); text-decoration: none;">Confidențialitate</a>'
if privacy_link not in text:
    marker = '<a href="/contact/" style="color: var(--primary-color); text-decoration: none;">Contact</a>'
    if text.count(marker) != 1:
        raise SystemExit("footer marker mismatch")
    text = text.replace(marker, marker + "\n            " + privacy_link, 1)

if "<AnalyticsConsent />" not in text:
    marker = "\n      <script>\n        document.addEventListener('DOMContentLoaded'"
    if text.count(marker) != 1:
        raise SystemExit("body script marker mismatch")
    text = text.replace(
        marker,
        "\n      <AnalyticsConsent />\n      \n      <script>\n        document.addEventListener('DOMContentLoaded'",
        1,
    )

if text.count(import_line) != 1 or text.count("<AnalyticsConsent />") != 1:
    raise SystemExit("layout patch verification failed")
p.write_text(text, encoding="utf-8")
PY

OWNER_GROUP="$(stat -c '%u:%g' "$BACKUP_DIR/source/Layout.astro")"
chown "$OWNER_GROUP" "$ROOT/src/layouts/Layout.astro" "$ROOT/src/components/AnalyticsConsent.astro" "$ROOT/src/pages/politica-de-confidentialitate.astro" 2>/dev/null || true
SOURCE_PATCHED=1

grep -q 'G-4C4JFDT4F2' "$ROOT/src/components/AnalyticsConsent.astro"
grep -q 'analytics_storage: "denied"' "$ROOT/src/components/AnalyticsConsent.astro"
grep -q '<AnalyticsConsent />' "$ROOT/src/layouts/Layout.astro"

status "RUNNING" "SOURCE_CHECK_AND_BUILD"

cd "$ROOT"
export NODE_OPTIONS="--max-old-space-size=8192"
timeout 720 npm run check > "$RUN_DIR/astro-check.log" 2>&1
rm -rf "$SOURCE_BUILD"
timeout 900 ./node_modules/.bin/astro build --outDir "$SOURCE_BUILD" > "$RUN_DIR/astro-build.log" 2>&1

[[ -f "$SOURCE_BUILD/index.html" ]]
[[ -f "$SOURCE_BUILD/politica-de-confidentialitate/index.html" ]]
grep -q "$MEASUREMENT_ID" "$SOURCE_BUILD/index.html"
grep -q 'lm_analytics_consent_v1' "$SOURCE_BUILD/index.html"

status "RUNNING" "CLONE_ACTIVE_RELEASE"

mkdir -p "$NEW_RELEASE"
cp -a --reflink=auto "$ACTIVE_BEFORE"/. "$NEW_RELEASE"/
BASE_HTML_COUNT="$(find "$ACTIVE_BEFORE" -type f -name '*.html' | wc -l | tr -d ' ')"
CLONE_HTML_COUNT="$(find "$NEW_RELEASE" -type f -name '*.html' | wc -l | tr -d ' ')"
[[ "$BASE_HTML_COUNT" -eq "$CLONE_HTML_COUNT" ]]
[[ "$BASE_HTML_COUNT" -ge 400 ]]

status "RUNNING" "INJECT_CONSENT"

python3 - "$NEW_RELEASE" "$BOOT/static-head.html" "$BOOT/static-body.html" <<'PY'
from pathlib import Path
import sys, re
root = Path(sys.argv[1])
head = Path(sys.argv[2]).read_text(encoding="utf-8")
body = Path(sys.argv[3]).read_text(encoding="utf-8")
changed = 0
for path in sorted(root.rglob("*.html")):
    text = path.read_text(encoding="utf-8")
    if "LM-GA4-CONSENT-V1" in text:
        continue
    if re.search(r"\bG-[A-Z0-9]{6,}\b|\bGTM-[A-Z0-9]{4,}\b|googletagmanager\.com", text):
        raise SystemExit(f"unexpected analytics marker before injection: {path}")
    head_pos = text.lower().rfind("</head>")
    body_pos = text.lower().rfind("</body>")
    if head_pos < 0 or body_pos < 0 or head_pos > body_pos:
        raise SystemExit(f"missing closing tags: {path}")
    text = text[:head_pos] + head + "\n" + text[head_pos:]
    body_pos = text.lower().rfind("</body>")
    text = text[:body_pos] + body + "\n" + text[body_pos:]
    path.write_text(text, encoding="utf-8")
    changed += 1
print(f"INJECTED_HTML={changed}")
PY

mkdir -p "$NEW_RELEASE/politica-de-confidentialitate"
cp -a "$SOURCE_BUILD/politica-de-confidentialitate/index.html" "$NEW_RELEASE/politica-de-confidentialitate/index.html"
if [[ -d "$SOURCE_BUILD/_astro" ]]; then
  mkdir -p "$NEW_RELEASE/_astro"
  cp -a "$SOURCE_BUILD/_astro"/. "$NEW_RELEASE/_astro"/
fi

status "RUNNING" "STATIC_GATES"

python3 - "$NEW_RELEASE" "$MEASUREMENT_ID" <<'PY' > "$RUN_DIR/static-gates.json"
from pathlib import Path
import sys, re, json
root = Path(sys.argv[1])
expected = sys.argv[2]
files = sorted(root.rglob("*.html"))
missing_id, missing_consent, missing_banner = [], [], []
ids, gtm = set(), set()
for p in files:
    text = p.read_text(encoding="utf-8")
    rel = str(p.relative_to(root))
    if expected not in text: missing_id.append(rel)
    if 'analytics_storage: "denied"' not in text: missing_consent.append(rel)
    if 'id="lm-analytics-consent"' not in text: missing_banner.append(rel)
    ids.update(re.findall(r"\bG-[A-Z0-9]{6,}\b", text))
    gtm.update(re.findall(r"\bGTM-[A-Z0-9]{4,}\b", text))
result = {
    "html_count": len(files),
    "measurement_ids": sorted(ids),
    "gtm_ids": sorted(gtm),
    "missing_measurement_id": missing_id[:30],
    "missing_consent_default": missing_consent[:30],
    "missing_banner": missing_banner[:30],
    "privacy_page": (root / "politica-de-confidentialitate/index.html").is_file(),
    "time4pizza_property_id_present": any("549983021" in p.read_text(encoding="utf-8") for p in files),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
if not files or missing_id or missing_consent or missing_banner:
    raise SystemExit(1)
if ids != {expected} or gtm:
    raise SystemExit(2)
if not result["privacy_page"] or result["time4pizza_property_id_present"]:
    raise SystemExit(3)
PY

status "RUNNING" "LOCAL_BROWSER_QA"

python3 -m http.server "$LOCAL_PORT" --bind 127.0.0.1 --directory "$NEW_RELEASE" > "$RUN_DIR/http-server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:$LOCAL_PORT/" >/dev/null && break
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$LOCAL_PORT/" >/dev/null
cp -a "$BOOT/playwright-qa.mjs" "$RUN_DIR/playwright-qa.mjs"
LM_GA4_BASE_URL="http://127.0.0.1:$LOCAL_PORT" LM_GA4_EVIDENCE_DIR="$RUN_DIR/local-playwright" \
  timeout 300 node "$RUN_DIR/playwright-qa.mjs" > "$RUN_DIR/playwright-qa.json"

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

status "RUNNING" "ATOMIC_DEPLOY"

TMP_LINK="$ROOT/.dist_current.ga4.$$"
rm -f "$TMP_LINK"
ln -s "$NEW_RELEASE" "$TMP_LINK"
mv -Tf "$TMP_LINK" "$ROOT/dist_current"
DEPLOY_SWITCHED=1

nginx -t > "$RUN_DIR/nginx-test.log" 2>&1
PUBLIC_HTML="$RUN_DIR/public-home.html"
curl -fsS --max-time 30 "https://logicasimatematica.ro/?lm-ga4-live=$STAMP" -o "$PUBLIC_HTML"
grep -q "$MEASUREMENT_ID" "$PUBLIC_HTML"
grep -q 'LM-GA4-CONSENT-V1' "$PUBLIC_HTML"
python3 - "$PUBLIC_HTML" "$MEASUREMENT_ID" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
expected = sys.argv[2]
ids = set(re.findall(r"\bG-[A-Z0-9]{6,}\b", text))
gtm_ids = set(re.findall(r"\bGTM-[A-Z0-9]{4,}\b", text))
if ids != {expected}:
    raise SystemExit(f"unexpected GA4 IDs: {sorted(ids)!r}")
if gtm_ids:
    raise SystemExit(f"unexpected GTM IDs: {sorted(gtm_ids)!r}")
if "549983021" in text:
    raise SystemExit("Time4Pizza property ID present")
PY

PUBLIC_PRIVACY_STATUS="$(curl -sS -o "$RUN_DIR/public-privacy.html" -w '%{http_code}' --max-time 30 'https://logicasimatematica.ro/politica-de-confidentialitate/?lm-ga4-live=1')"
[[ "$PUBLIC_PRIVACY_STATUS" == "200" ]]
grep -q 'Politica de confidențialitate și cookie-uri' "$RUN_DIR/public-privacy.html"

status "RUNNING" "LIVE_BROWSER_QA"

LM_GA4_BASE_URL="https://logicasimatematica.ro" LM_GA4_EVIDENCE_DIR="$RUN_DIR/live-playwright" \
  timeout 300 node "$RUN_DIR/playwright-qa.mjs" > "$RUN_DIR/playwright-live-qa.json"

status "RUNNING" "EVIDENCE"

find "$NEW_RELEASE" -type f -print0 | sort -z | xargs -0 sha256sum > "$RUN_DIR/release.sha256"
sha256sum "$RUN_DIR"/*.json "$RUN_DIR"/*.log "$RUN_DIR"/release.sha256 > "$RUN_DIR/EVIDENCE.sha256"
EVIDENCE_SHA="$(sha256sum "$RUN_DIR/EVIDENCE.sha256" | awk '{print $1}')"

python3 - "$SUMMARY_FILE" "$ACTIVE_BEFORE" "$NEW_RELEASE" "$MEASUREMENT_ID" "$PROPERTY_ID" "$STREAM_ID" "$BASE_HTML_COUNT" "$EVIDENCE_SHA" <<'PY'
from pathlib import Path
import json, sys
summary = {
  "status": "PASS",
  "project": "Logică și Matematică",
  "domain": "https://logicasimatematica.ro",
  "ga4_property_id": sys.argv[5],
  "ga4_measurement_id": sys.argv[4],
  "ga4_stream_id": sys.argv[6],
  "active_before": sys.argv[2],
  "active_after": sys.argv[3],
  "html_pages_instrumented": int(sys.argv[7]) + 1,
  "consent_mode_v2": "basic_default_denied",
  "advertising_consent": "always_denied",
  "events": [
    "page_view", "phone_click", "whatsapp_click", "contact_click",
    "booking_request", "cta_click", "generate_lead", "consent_update"
  ],
  "privacy_page": "/politica-de-confidentialitate/",
  "time4pizza_isolation": "PASS",
  "evidence_manifest_sha256": sys.argv[8],
}
Path(sys.argv[1]).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

DEPLOY_SWITCHED=0
status "PASS" "DEPLOY_AND_LOCAL_LIVE_QA_COMPLETE"
{
  printf 'MEASUREMENT_ID=%s\n' "$MEASUREMENT_ID"
  printf 'PROPERTY_ID=%s\n' "$PROPERTY_ID"
  printf 'STREAM_ID=%s\n' "$STREAM_ID"
  printf 'ACTIVE_AFTER=%s\n' "$(readlink -f "$ROOT/dist_current")"
  printf 'HTML_PAGES_INSTRUMENTED=%s\n' "$((BASE_HTML_COUNT + 1))"
  printf 'TIME4PIZZA_ISOLATION=PASS\n'
  printf 'CONSENT_DEFAULT=DENIED\n'
  printf 'EVIDENCE_SHA256=%s\n' "$EVIDENCE_SHA"
} >> "$STATUS_FILE"
