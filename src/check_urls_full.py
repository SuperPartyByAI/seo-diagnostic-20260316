import sys, json, os, re, ssl, time, urllib.request
from datetime import datetime, timezone
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

gsc_available = False
gsc_service = None
try:
    with open(r'C:\Users\ursac\Superparty\.env', 'r', encoding='utf-8') as f:
        env = {}
        for line in f:
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    sa_info = json.loads(env.get('GSC_SERVICE_ACCOUNT_JSON', '{}'))
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    creds = service_account.Credentials.from_service_account_info(sa_info, scopes=['https://www.googleapis.com/auth/webmasters.readonly'])
    gsc_service = build('searchconsole', 'v1', credentials=creds)
    gsc_available = True
except:
    pass

def fetch_sitemap(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'identity'})
        data = urllib.request.urlopen(req, context=ctx, timeout=15).read().decode('utf-8','ignore')
        return re.findall(r'<loc>(.*?)</loc>', data)
    except:
        return []

print("Collecting URLs...", file=sys.stderr)
sitemap_urls = {}
for sm in ["https://www.superparty.ro/sitemap.xml","https://www.animatopia.ro/sitemap.xml","https://www.wowparty.ro/sitemap.xml"]:
    urls = fetch_sitemap(sm)
    print(f"  {sm}: {len(urls)}", file=sys.stderr)
    for u in urls:
        sitemap_urls[u] = sm

# Sample: 15 per domain + key pages
sample = []
counts = {}
key = ["https://www.superparty.ro/","https://www.superparty.ro/animatori-petreceri-copii",
       "https://www.animatopia.ro/","https://www.animatopia.ro/animatori-petreceri-copii/",
       "https://animatopia.ro/animatori-petreceri-copii/",
       "https://www.wowparty.ro/"]
for u in key:
    sample.append(u)

for u in sitemap_urls:
    from urllib.parse import urlparse
    d = urlparse(u).netloc
    counts[d] = counts.get(d, 0)
    if counts[d] < 15 and u not in sample:
        sample.append(u)
        counts[d] += 1

print(f"Scanning {len(sample)} URLs...", file=sys.stderr)
results = []

for i, url in enumerate(sample):
    r = {"url": url, "initial_status": None, "redirect_chain": [], "final_status": None, "final_url": url,
         "canonical": None, "json_ld_present": False, "json_ld_valid": None, "json_ld_sample": "",
         "sitemap_present": url in sitemap_urls, "matched_sitemap": sitemap_urls.get(url),
         "robots_status": None, "gsc_inspection": None, "issues": []}
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'identity'})
        resp = urllib.request.urlopen(req, context=ctx, timeout=15)
        r["final_status"] = resp.status
        r["initial_status"] = resp.status
        r["final_url"] = resp.geturl()
        html = resp.read().decode('utf-8','ignore')
        
        from urllib.parse import urlparse
        od = urlparse(url).netloc.replace('www.','')
        fd = urlparse(r["final_url"]).netloc.replace('www.','')
        if od != fd:
            r["issues"].append("redirects_to_other_domain")
            r["redirect_chain"] = [{"status":301,"url":r["final_url"]}]
        
        c = re.search(r'<link[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', html, re.I)
        if c:
            r["canonical"] = c.group(1)
            cd = urlparse(c.group(1)).netloc.replace('www.','')
            if cd != od:
                r["issues"].append("canonical_points_to_other_domain")
        else:
            r["issues"].append("missing_canonical")
        
        ld = re.findall(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', html, re.S|re.I)
        if ld:
            r["json_ld_present"] = True
            r["json_ld_sample"] = ld[0][:300]
            try: json.loads(ld[0]); r["json_ld_valid"] = True
            except: r["json_ld_valid"] = False
        else:
            r["issues"].append("json_ld_missing")
        
        if not r["sitemap_present"]:
            r["issues"].append("not_in_sitemap")
    except urllib.error.HTTPError as e:
        r["final_status"] = e.code; r["initial_status"] = e.code; r["issues"].append(f"http_error_{e.code}")
    except Exception as e:
        r["final_status"] = 0; r["issues"].append("connection_error")
    
    # GSC
    if gsc_service:
        from urllib.parse import urlparse
        domain = urlparse(url).netloc.replace('www.','')
        try:
            body = {"inspectionUrl": url, "siteUrl": f"sc-domain:{domain}", "languageCode": "ro-RO"}
            resp2 = gsc_service.urlInspection().index().inspect(body=body).execute()
            idx = resp2.get('inspectionResult',{}).get('indexStatusResult',{})
            r["gsc_inspection"] = {"coverageState":idx.get('coverageState','N/A'),"lastCrawlTime":idx.get('lastCrawlTime','N/A'),"verdict":idx.get('verdict','N/A')}
        except Exception as e:
            r["gsc_inspection"] = {"error": str(e)[:200]}
    else:
        r["gsc_inspection"] = {"missing_secret": True}
    
    results.append(r)
    if (i+1) % 10 == 0:
        print(f"  {i+1}/{len(sample)}", file=sys.stderr)
    time.sleep(0.3)

summary = {
    "total_urls": len(results),
    "redirects_to_other_domain": sum(1 for r in results if "redirects_to_other_domain" in r["issues"]),
    "missing_canonical": sum(1 for r in results if "missing_canonical" in r["issues"]),
    "canonical_points_elsewhere": sum(1 for r in results if "canonical_points_to_other_domain" in r["issues"]),
    "json_ld_missing": sum(1 for r in results if "json_ld_missing" in r["issues"]),
    "not_in_sitemap": sum(1 for r in results if "not_in_sitemap" in r["issues"]),
    "gsc_permission_errors": sum(1 for r in results if "403" in str(r.get("gsc_inspection",{}).get("error",""))),
    "top_problem_urls": sorted([{"url":r["url"],"issues":r["issues"]} for r in results if r["issues"]], key=lambda x:-len(x["issues"]))[:20]
}

output = {"status":"partial" if any(r["issues"] for r in results) else "ok", "timestamp":datetime.now(timezone.utc).isoformat(),
    "input_source":"sitemaps:all_domains","gsc_available":gsc_available,"summary":summary,"urls":results,
    "recommendations":[],"no_changes_made":True}

if summary["redirects_to_other_domain"]>0: output["recommendations"].append("CRITICAL: URLs redirect to other domain. Check Vercel domain binding.")
if summary["canonical_points_elsewhere"]>0: output["recommendations"].append("CRITICAL: Canonical points to other domain. Fix Layout.astro.")
if summary["missing_canonical"]>0: output["recommendations"].append("WARNING: Missing canonical tags.")
if summary["json_ld_missing"]>0: output["recommendations"].append("INFO: Missing JSON-LD on some pages.")

out_path = r'C:\Windows\Temp\DIAGNOSTIC_RESULTS.json'
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(json.dumps(output, indent=2, ensure_ascii=False))
print(f"\nSaved: {out_path}", file=sys.stderr)
print("no_changes_made: true", file=sys.stderr)
