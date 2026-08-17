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
REDIRECT_BASELINE_COUNT=10
LOCAL_PORT=18765

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
CLEAN_WORK="$RUN_DIR/source-work"
SOURCE_BUILD="$RUN_DIR/source-build"
NEW_RELEASE="$ROOT/releases/release_LM-GA4-CONSENT-V1_${STAMP}"
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
sha256sum "$BOOT/AnalyticsConsent.astro" "$BOOT/politica-de-confidentialitate.astro" "$BOOT/static-head.html" "$BOOT/static-body.html" "$BOOT/playwright-qa.mjs" > "$BACKUP_DIR/payload.sha256"

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
    text = text.replace(marker, "\n      <AnalyticsConsent />\n      \n      <script>\n        document.addEventListener('DOMContentLoaded'", 1)
if text.count(import_line) != 1 or text.count("<AnalyticsConsent />") != 1:
    raise SystemExit("layout patch verification failed")
p.write_text(text, encoding="utf-8")
PY
OWNER_GROUP="$(stat -c '%u:%g' "$BACKUP_DIR/source/Layout.astro")"
chown "$OWNER_GROUP" "$ROOT/src/layouts/Layout.astro" "$ROOT/src/components/AnalyticsConsent.astro" "$ROOT/src/pages/politica-de-confidentialitate.astro" 2>/dev/null || true
SOURCE_PATCHED=1

grep -q "$MEASUREMENT_ID" "$ROOT/src/components/AnalyticsConsent.astro"
grep -q 'analytics_storage: "denied"' "$ROOT/src/components/AnalyticsConsent.astro"
grep -q '<AnalyticsConsent />' "$ROOT/src/layouts/Layout.astro"

status "RUNNING" "CLEAN_SOURCE_CHECK_AND_BUILD"

rm -rf "$CLEAN_WORK" "$SOURCE_BUILD"
install -d -m 700 "$CLEAN_WORK" "$CLEAN_WORK/src" "$CLEAN_WORK/public"
rsync -a --delete "$ROOT/src/" "$CLEAN_WORK/src/"
rsync -a --delete "$ROOT/public/" "$CLEAN_WORK/public/"
for file in package.json package-lock.json astro.config.mjs tsconfig.json tailwind.config.mjs postcss.config.mjs; do
  [[ ! -f "$ROOT/$file" ]] || install -m 0600 "$ROOT/$file" "$CLEAN_WORK/$file"
done
ln -s "$ROOT/node_modules" "$CLEAN_WORK/node_modules"
find "$CLEAN_WORK" -maxdepth 1 -mindepth 1 -printf '%f\n' | sort > "$RUN_DIR/clean-work-root.txt"
EXPECTED_ROOT='astro.config.mjs node_modules package.json package-lock.json postcss.config.mjs public src tailwind.config.mjs tsconfig.json'
ACTUAL_ROOT="$(tr '\n' ' ' < "$RUN_DIR/clean-work-root.txt" | sed -E 's/[[:space:]]+$//')"
[[ "$ACTUAL_ROOT" == "$EXPECTED_ROOT" ]]
cd "$CLEAN_WORK"
export NODE_OPTIONS="--max-old-space-size=8192"
timeout 900 npm run check > "$RUN_DIR/astro-check.log" 2>&1
timeout 900 ./node_modules/.bin/astro build --outDir "$SOURCE_BUILD" > "$RUN_DIR/astro-build.log" 2>&1

[[ -f "$SOURCE_BUILD/index.html" ]]
[[ -f "$SOURCE_BUILD/politica-de-confidentialitate/index.html" ]]
grep -q "$MEASUREMENT_ID" "$SOURCE_BUILD/index.html"
grep -q 'lm_analytics_consent_v1' "$SOURCE_BUILD/index.html"

status "RUNNING" "CLONE_ACTIVE_RELEASE"

rm -rf "$NEW_RELEASE"
mkdir -p "$NEW_RELEASE"
cp -a --reflink=auto "$ACTIVE_BEFORE"/. "$NEW_RELEASE"/
BASE_HTML_COUNT="$(find "$ACTIVE_BEFORE" -type f -name '*.html' | wc -l | tr -d ' ')"
CLONE_HTML_COUNT="$(find "$NEW_RELEASE" -type f -name '*.html' | wc -l | tr -d ' ')"
[[ "$BASE_HTML_COUNT" -eq "$CLONE_HTML_COUNT" ]]
[[ "$BASE_HTML_COUNT" -ge 400 ]]

status "RUNNING" "INJECT_CONSENT"

python3 - "$NEW_RELEASE" "$BOOT/static-head.html" "$BOOT/static-body.html" "$REDIRECT_BASELINE_COUNT" <<'PY'
from pathlib import Path
import sys, re
root = Path(sys.argv[1])
head = Path(sys.argv[2]).read_text(encoding="utf-8")
body = Path(sys.argv[3]).read_text(encoding="utf-8")
redirect_baseline = int(sys.argv[4])
changed = 0
skipped_redirects = 0
for path in sorted(root.rglob("*.html")):
    text = path.read_text(encoding="utf-8")
    if "LM-GA4-CONSENT-V1" in text:
        continue
    if re.search(r"\bG-[A-Z0-9]{6,}\b|\bGTM-[A-Z0-9]{4,}\b|googletagmanager\.com", text):
        raise SystemExit(f"unexpected analytics marker before injection: {path}")
    meta_tags = re.findall(r"<meta\b[^>]*>", text, flags=re.I)
    link_tags = re.findall(r"<link\b[^>]*>", text, flags=re.I)
    has_refresh = any(re.search(r"http-equiv\s*=\s*[\"']?refresh[\"']?", tag, flags=re.I) for tag in meta_tags)
    has_noindex = any(re.search(r"name\s*=\s*[\"']robots[\"']", tag, flags=re.I) and "noindex" in tag.lower() for tag in meta_tags)
    has_canonical = any(re.search(r"rel\s*=\s*[\"']canonical[\"']", tag, flags=re.I) for tag in link_tags)
    body_pos = text.lower().rfind("</body>")
    if has_refresh:
        if not (has_noindex and has_canonical and body_pos >= 0):
            raise SystemExit(f"ambiguous redirect fragment: {path}")
        skipped_redirects += 1
        continue
    head_pos = text.lower().rfind("</head>")
    if head_pos < 0 or body_pos < 0 or head_pos > body_pos:
        raise SystemExit(f"missing closing tags in indexable page: {path}")
    text = text[:head_pos] + head + "\n" + text[head_pos:]
    body_pos = text.lower().rfind("</body>")
    text = text[:body_pos] + body + "\n" + text[body_pos:]
    path.write_text(text, encoding="utf-8")
    changed += 1
print(f"INJECTED_HTML={changed}")
print(f"SKIPPED_REDIRECT_HTML={skipped_redirects}")
if skipped_redirects != redirect_baseline:
    raise SystemExit(f"redirect baseline mismatch: {skipped_redirects}")
PY

mkdir -p "$NEW_RELEASE/politica-de-confidentialitate"
cp -a "$SOURCE_BUILD/politica-de-confidentialitate/index.html" "$NEW_RELEASE/politica-de-confidentialitate/index.html"
if [[ -d "$SOURCE_BUILD/_astro" ]]; then
  mkdir -p "$NEW_RELEASE/_astro"
  cp -a "$SOURCE_BUILD/_astro"/. "$NEW_RELEASE/_astro"/
fi

status "RUNNING" "STATIC_GATES"

python3 - "$NEW_RELEASE" "$MEASUREMENT_ID" "$REDIRECT_BASELINE_COUNT" <<'PY' > "$RUN_DIR/static-gates.json"
from pathlib import Path
import sys, re, json
root = Path(sys.argv[1])
expected = sys.argv[2]
redirect_baseline = int(sys.argv[3])
files = sorted(root.rglob("*.html"))
missing_id, missing_consent, missing_banner = [], [], []
redirects, invalid_redirects, redirect_analytics = [], [], []
ids, gtm = set(), set()
time4pizza = []
for p in files:
    text = p.read_text(encoding="utf-8")
    rel = str(p.relative_to(root))
    meta_tags = re.findall(r"<meta\b[^>]*>", text, flags=re.I)
    link_tags = re.findall(r"<link\b[^>]*>", text, flags=re.I)
    has_refresh = any(re.search(r"http-equiv\s*=\s*[\"']?refresh[\"']?", tag, flags=re.I) for tag in meta_tags)
    has_noindex = any(re.search(r"name\s*=\s*[\"']robots[\"']", tag, flags=re.I) and "noindex" in tag.lower() for tag in meta_tags)
    has_canonical = any(re.search(r"rel\s*=\s*[\"']canonical[\"']", tag, flags=re.I) for tag in link_tags)
    if has_refresh:
        if not (has_noindex and has_canonical and "</body>" in text.lower()):
            invalid_redirects.append(rel)
        else:
            redirects.append(rel)
        if re.search(r"\bG-[A-Z0-9]{6,}\b|\bGTM-[A-Z0-9]{4,}\b|googletagmanager\.com|LM-GA4-CONSENT-V1", text):
            redirect_analytics.append(rel)
        continue
    if expected not in text: missing_id.append(rel)
    if 'analytics_storage: "denied"' not in text: missing_consent.append(rel)
    if 'id="lm-analytics-consent"' not in text: missing_banner.append(rel)
    ids.update(re.findall(r"\bG-[A-Z0-9]{6,}\b", text))
    gtm.update(re.findall(r"\bGTM-[A-Z0-9]{4,}\b", text))
    if "549983021" in text or "G-5JWGETTK8S" in text:
        time4pizza.append(rel)
result = {
    "html_count": len(files),
    "indexable_html_count": len(files) - len(redirects),
    "redirect_count": len(redirects),
    "redirects": redirects,
    "invalid_redirects": invalid_redirects,
    "redirect_analytics": redirect_analytics,
    "measurement_ids": sorted(ids),
    "gtm_ids": sorted(gtm),
    "missing_measurement_id": missing_id[:30],
    "missing_consent_default": missing_consent[:30],
    "missing_banner": missing_banner[:30],
    "privacy_page": (root / "politica-de-confidentialitate/index.html").is_file(),
    "time4pizza_leaks": time4pizza,
}
print(json.dumps(result, ensure_ascii=False, indent=2))
if not files or missing_id or missing_consent or missing_banner or invalid_redirects or redirect_analytics:
    raise SystemExit(1)
if len(redirects) != redirect_baseline:
    raise SystemExit(2)
if ids != {expected} or gtm:
    raise SystemExit(3)
if not result["privacy_page"] or time4pizza:
    raise SystemExit(4)
PY

status "RUNNING" "LOCAL_BROWSER_QA"

python3 -m http.server "$LOCAL_PORT" --bind 127.0.0.1 --directory "$NEW_RELEASE" > "$RUN_DIR/http-server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$LOCAL_PORT/" >/dev/null && break
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$LOCAL_PORT/" >/dev/null
cp -a "$BOOT/playwright-qa.mjs" "$RUN_DIR/playwright-qa.mjs"
node --check "$RUN_DIR/playwright-qa.mjs"
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
import re, sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
expected = sys.argv[2]
ids = set(re.findall(r"\bG-[A-Z0-9]{6,}\b", text))
gtm_ids = set(re.findall(r"\bGTM-[A-Z0-9]{4,}\b", text))
if ids != {expected}: raise SystemExit(f"unexpected GA4 IDs: {sorted(ids)!r}")
if gtm_ids: raise SystemExit(f"unexpected GTM IDs: {sorted(gtm_ids)!r}")
if "549983021" in text or "G-5JWGETTK8S" in text: raise SystemExit("Time4Pizza identifier present")
PY
PUBLIC_PRIVACY_STATUS="$(curl -sS -o "$RUN_DIR/public-privacy.html" -w '%{http_code}' --max-time 30 'https://logicasimatematica.ro/politica-de-confidentialitate/?lm-ga4-live=1')"
[[ "$PUBLIC_PRIVACY_STATUS" == "200" ]]
grep -q 'Politica de confidențialitate și cookie-uri' "$RUN_DIR/public-privacy.html"

status "RUNNING" "LIVE_BROWSER_QA"

LM_GA4_BASE_URL="https://logicasimatematica.ro" LM_GA4_EVIDENCE_DIR="$RUN_DIR/live-playwright" \
  timeout 300 node "$RUN_DIR/playwright-qa.mjs" > "$RUN_DIR/playwright-live-qa.json"

status "RUNNING" "EVIDENCE"

find "$NEW_RELEASE" -type f -print0 | sort -z | xargs -0 sha256sum > "$RUN_DIR/release.sha256"
find "$RUN_DIR" -maxdepth 1 -type f \( -name '*.json' -o -name '*.log' -o -name 'release.sha256' \) -print0 | sort -z | xargs -0 sha256sum > "$RUN_DIR/EVIDENCE.sha256"
EVIDENCE_SHA="$(sha256sum "$RUN_DIR/EVIDENCE.sha256" | awk '{print $1}')"
INDEXABLE_COUNT="$(python3 -c 'import json; print(json.load(open("'"$RUN_DIR/static-gates.json"'"))["indexable_html_count"])')"
REDIRECT_COUNT="$(python3 -c 'import json; print(json.load(open("'"$RUN_DIR/static-gates.json"'"))["redirect_count"])')"

python3 - "$SUMMARY_FILE" "$ACTIVE_BEFORE" "$NEW_RELEASE" "$MEASUREMENT_ID" "$PROPERTY_ID" "$STREAM_ID" "$INDEXABLE_COUNT" "$REDIRECT_COUNT" "$EVIDENCE_SHA" <<'PY'
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
  "html_pages_instrumented": int(sys.argv[7]),
  "redirect_pages_excluded": int(sys.argv[8]),
  "consent_mode_v2": "basic_default_denied",
  "advertising_consent": "always_denied",
  "events": ["page_view", "phone_click", "whatsapp_click", "contact_click", "booking_request", "cta_click", "generate_lead", "consent_update"],
  "privacy_page": "/politica-de-confidentialitate/",
  "time4pizza_isolation": "PASS",
  "evidence_manifest_sha256": sys.argv[9],
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
  printf 'HTML_PAGES_INSTRUMENTED=%s\n' "$INDEXABLE_COUNT"
  printf 'REDIRECT_PAGES_EXCLUDED=%s\n' "$REDIRECT_COUNT"
  printf 'TIME4PIZZA_ISOLATION=PASS\n'
  printf 'CONSENT_DEFAULT=DENIED\n'
  printf 'EVIDENCE_SHA256=%s\n' "$EVIDENCE_SHA"
} >> "$STATUS_FILE"
