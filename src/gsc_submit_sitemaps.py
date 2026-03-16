import sys
import json
import time
from google.oauth2 import service_account
from googleapiclient.discovery import build

sys.stdout.reconfigure(encoding='utf-8')

# Load credentials
with open(r'C:\Users\ursac\Superparty\.env', 'r', encoding='utf-8') as f:
    env = {}
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")

sa_info = json.loads(env.get('GSC_SERVICE_ACCOUNT_JSON', '{}'))

# --- SUPERPARTY: Submit sitemap ---
print("=" * 60)
print("SUPERPARTY: Submit sitemap")
print("=" * 60)
try:
    creds_wm = service_account.Credentials.from_service_account_info(
        sa_info, scopes=['https://www.googleapis.com/auth/webmasters'])
    wm = build('webmasters', 'v3', credentials=creds_wm)
    wm.sitemaps().submit(
        siteUrl='sc-domain:superparty.ro',
        feedpath='https://www.superparty.ro/sitemap.xml'
    ).execute()
    print("✅ Superparty sitemap SUBMITTED!")
except Exception as e:
    print(f"❌ Superparty sitemap error: {e}")

# --- ANIMATOPIA: Submit sitemap ---
print("\n" + "=" * 60)
print("ANIMATOPIA: Submit sitemap")
print("=" * 60)
try:
    wm.sitemaps().submit(
        siteUrl='sc-domain:animatopia.ro',
        feedpath='https://animatopia.ro/sitemap.xml'
    ).execute()
    print("✅ Animatopia sitemap SUBMITTED!")
except Exception as e:
    print(f"❌ Animatopia sitemap error: {e}")

# Try alternative URL
try:
    wm.sitemaps().submit(
        siteUrl='sc-domain:animatopia.ro',
        feedpath='https://www.animatopia.ro/sitemap.xml'
    ).execute()
    print("✅ Animatopia www sitemap SUBMITTED!")
except Exception as e:
    print(f"   (www variant: {e})")

# --- ANIMATOPIA: Request Indexing via URL Inspection ---
print("\n" + "=" * 60)
print("ANIMATOPIA: URL Inspection (owner page)")
print("=" * 60)
try:
    creds_ro = service_account.Credentials.from_service_account_info(
        sa_info, scopes=['https://www.googleapis.com/auth/webmasters.readonly'])
    sc = build('searchconsole', 'v1', credentials=creds_ro)
    req = {
        "inspectionUrl": "https://animatopia.ro/animatori-petreceri-copii/",
        "siteUrl": "sc-domain:animatopia.ro",
        "languageCode": "ro-RO"
    }
    resp = sc.urlInspection().index().inspect(body=req).execute()
    res = resp.get('inspectionResult', {}).get('indexStatusResult', {})
    print(f"Verdict: {res.get('verdict', 'N/A')}")
    print(f"Coverage: {res.get('coverageState', 'N/A')}")
    print(f"Last Crawl: {res.get('lastCrawlTime', 'N/A')}")
except Exception as e:
    print(f"❌ Animatopia inspection error: {e}")

# --- WOWPARTY: Try URL Inspection ---
print("\n" + "=" * 60)
print("WOWPARTY: URL Inspection attempt")
print("=" * 60)
try:
    req = {
        "inspectionUrl": "https://www.wowparty.ro/",
        "siteUrl": "sc-domain:wowparty.ro",
        "languageCode": "ro-RO"
    }
    resp = sc.urlInspection().index().inspect(body=req).execute()
    res = resp.get('inspectionResult', {}).get('indexStatusResult', {})
    print(f"Verdict: {res.get('verdict', 'N/A')}")
    print(f"Coverage: {res.get('coverageState', 'N/A')}")
    print(f"Last Crawl: {res.get('lastCrawlTime', 'N/A')}")
except Exception as e:
    print(f"❌ Wowparty error (expected 403 - needs SA added as Owner): {e}")

print("\n" + "=" * 60)
print("DONE — Sitemap submissions complete.")
print("=" * 60)
