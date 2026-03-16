import sys, json, os, re, ssl, time, urllib.request
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Load GSC
gsc_service = None
gsc_available = False
try:
    with open(r'C:\Users\ursac\Superparty\.env', 'r', encoding='utf-8') as f:
        env = {}
        for line in f:
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    sa_info = json.loads(env.get('GSC_SERVICE_ACCOUNT_JSON', '{}'))
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    creds = service_account.Credentials.from_service_account_info(sa_info, scopes=['https://www.googleapis.com/auth/webmasters.readonly'])
    gsc_service = build('searchconsole', 'v1', credentials=creds)
    gsc_available = True
except Exception as e:
    print(f"GSC init error: {e}", file=sys.stderr)

# Load sitemap for cross-check
sitemap_urls = set()
try:
    req = urllib.request.Request('https://www.superparty.ro/sitemap.xml', headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'identity'})
    data = urllib.request.urlopen(req, context=ctx, timeout=15).read().decode('utf-8','ignore')
    sitemap_urls = set(re.findall(r'<loc>(.*?)</loc>', data))
    print(f"Sitemap loaded: {len(sitemap_urls)} URLs", file=sys.stderr)
except Exception as e:
    print(f"Sitemap error: {e}", file=sys.stderr)

# Load URLs
urls = [l.strip() for l in open(r'C:\Windows\Temp\urls.txt','r',encoding='utf-8') if l.strip()]
print(f"Processing {len(urls)} URLs...", file=sys.stderr)

results = []
for i, url in enumerate(urls):
    r = {"url": url, "status": None, "final_url": None, "canonical": None,
         "json_ld": False, "in_sitemap": url in sitemap_urls, "issues": [], "gsc": None}
    
    # HTTP check
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'identity'})
        resp = urllib.request.urlopen(req, context=ctx, timeout=10)
        r["status"] = resp.status
        r["final_url"] = resp.geturl()
        html = resp.read().decode('utf-8','ignore')
        
        from urllib.parse import urlparse
        if urlparse(r["final_url"]).netloc.replace('www.','') != urlparse(url).netloc.replace('www.',''):
            r["issues"].append("redirect_other_domain")
        
        c = re.search(r'<link[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', html, re.I)
        if c:
            r["canonical"] = c.group(1)
            if urlparse(c.group(1)).netloc.replace('www.','') != 'superparty.ro':
                r["issues"].append("canonical_wrong_domain")
        else:
            r["issues"].append("missing_canonical")
        
        if 'application/ld+json' in html:
            r["json_ld"] = True
        else:
            r["issues"].append("no_jsonld")
        
        if not r["in_sitemap"]:
            r["issues"].append("not_in_sitemap")
            
    except urllib.error.HTTPError as e:
        r["status"] = e.code
        r["issues"].append(f"http_{e.code}")
    except Exception as e:
        r["status"] = 0
        r["issues"].append("timeout")
    
    # GSC check (every 3rd URL to save quota + time)
    if gsc_service and i % 3 == 0:
        try:
            body = {"inspectionUrl": url, "siteUrl": "sc-domain:superparty.ro", "languageCode": "ro-RO"}
            resp2 = gsc_service.urlInspection().index().inspect(body=body).execute()
            idx = resp2.get('inspectionResult',{}).get('indexStatusResult',{})
            r["gsc"] = {"coverage": idx.get('coverageState','N/A'), "crawl": idx.get('lastCrawlTime','N/A'), "verdict": idx.get('verdict','N/A')}
        except Exception as e:
            r["gsc"] = {"error": str(e)[:100]}
        time.sleep(0.3)
    
    results.append(r)
    if (i+1) % 20 == 0:
        print(f"  {i+1}/{len(urls)}", file=sys.stderr)

# Summary
s = {"total": len(results),
     "http_200": sum(1 for r in results if r["status"] == 200),
     "redirect_other": sum(1 for r in results if "redirect_other_domain" in r["issues"]),
     "missing_canonical": sum(1 for r in results if "missing_canonical" in r["issues"]),
     "canonical_wrong": sum(1 for r in results if "canonical_wrong_domain" in r["issues"]),
     "no_jsonld": sum(1 for r in results if "no_jsonld" in r["issues"]),
     "not_in_sitemap": sum(1 for r in results if "not_in_sitemap" in r["issues"]),
     "errors": sum(1 for r in results if r["status"] != 200),
     "problems": sorted([{"url":r["url"],"issues":r["issues"]} for r in results if r["issues"]], key=lambda x:-len(x["issues"]))[:20]}

output = {"status": "ok" if s["errors"]==0 and s["redirect_other"]==0 else "partial",
          "timestamp": datetime.now(timezone.utc).isoformat(), "gsc_available": gsc_available,
          "summary": s, "urls": results, "no_changes_made": True}

out_path = r'C:\Windows\Temp\GSC_DIAGNOSTIC.json'
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f"\nDone. Saved to {out_path}", file=sys.stderr)
print("no_changes_made: true", file=sys.stderr)
