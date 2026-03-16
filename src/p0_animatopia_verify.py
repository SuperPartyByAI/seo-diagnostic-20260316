import urllib.request
import ssl
import re
import sys
import os

sys.stdout.reconfigure(encoding='utf-8')
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

output = os.path.join(os.path.expanduser("~"), "Desktop", "P0_ANIMATOPIA_VERIFICARE.txt")
lines = []

def log(msg):
    print(msg)
    lines.append(msg)

log("=" * 80)
log("P0 — VERIFICARE ANIMATOPIA (TOATE TESTELE CERUTE DE CHATGPT)")
log("=" * 80)

# 1.1 Redirect chain
log("\n--- TEST 1.1: REDIRECT CHAIN (curl -IL animatopia.ro/animatori-petreceri-copii/) ---")
try:
    req = urllib.request.Request('https://animatopia.ro/animatori-petreceri-copii/', headers={'User-Agent': 'curl/7.68.0'})
    resp = urllib.request.urlopen(req, context=ctx, timeout=15)
    final_url = resp.geturl()
    status = resp.status
    log(f"Status Final: HTTP {status}")
    log(f"URL Final: {final_url}")
    if 'superparty' in final_url:
        log("❌ REDIRECT CATRE SUPERPARTY DETECTAT! TREBUIE REPARAT!")
    else:
        log("✅ PASS: Niciun redirect catre superparty.ro. Pagina serveste direct de pe animatopia.ro.")
except urllib.error.HTTPError as e:
    log(f"❌ HTTP Error: {e.code} - {e.reason}")
except Exception as e:
    log(f"❌ Connection Error: {e}")

# 1.2 Canonical + JSON-LD
log("\n--- TEST 1.2: CANONICAL + JSON-LD (head content) ---")
try:
    req = urllib.request.Request('https://animatopia.ro/animatori-petreceri-copii/', headers={'User-Agent': 'curl/7.68.0'})
    resp = urllib.request.urlopen(req, context=ctx, timeout=15)
    html = resp.read().decode('utf-8', errors='ignore')
    
    canonical = re.search(r'<link[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', html, re.I)
    if canonical:
        log(f"Canonical Tag: {canonical.group(1)}")
        if 'superparty' in canonical.group(1):
            log("❌ CANONICAL POINTEAZA SPRE SUPERPARTY! TREBUIE REPARAT!")
        else:
            log("✅ PASS: Canonical pointeaza corect spre animatopia.ro")
    else:
        log("⚠️ WARNING: Tag canonical LIPSA!")
    
    jsonld_count = html.count('application/ld+json')
    log(f"JSON-LD blocks: {jsonld_count}")
    if jsonld_count > 0:
        log("✅ PASS: JSON-LD structured data prezent.")
    else:
        log("⚠️ WARNING: JSON-LD LIPSA!")
except Exception as e:
    log(f"❌ Error: {e}")

# 1.3 Sitemap presence
log("\n--- TEST 1.3: SITEMAP PRESENCE ---")
sitemap_urls = [
    'https://animatopia.ro/sitemap-index.xml',
    'https://animatopia.ro/sitemap.xml',
    'https://animatopia.ro/sitemap-0.xml',
    'https://www.animatopia.ro/sitemap-index.xml',
    'https://www.animatopia.ro/sitemap.xml',
    'https://www.animatopia.ro/sitemap-0.xml'
]
found_sitemap = None
for sm in sitemap_urls:
    try:
        req = urllib.request.Request(sm, headers={'User-Agent': 'curl/7.68.0'})
        resp = urllib.request.urlopen(req, context=ctx, timeout=10)
        if resp.status == 200:
            content = resp.read().decode('utf-8', errors='ignore')
            count = content.count('<loc>')
            log(f"✅ GASIT: {sm} -> HTTP 200, contine {count} URL-uri")
            found_sitemap = sm
            break
    except:
        log(f"   ✗ {sm} -> NU EXISTA (404)")

if not found_sitemap:
    log("❌ CRITIC: NICIUN SITEMAP GASIT PE ANIMATOPIA! TREBUIE GENERAT SI URCAT!")

# 1.4 Robots.txt
log("\n--- TEST 1.4: ROBOTS.TXT ---")
try:
    req = urllib.request.Request('https://animatopia.ro/robots.txt', headers={'User-Agent': 'curl/7.68.0'})
    resp = urllib.request.urlopen(req, context=ctx, timeout=10)
    robots = resp.read().decode('utf-8', errors='ignore')
    log(f"Status: HTTP {resp.status}")
    log(f"Continut:\n{robots}")
    if 'Disallow: /' in robots and 'Disallow: /\n' not in robots:
        log("❌ ROBOTS.TXT BLOCHEAZA CRAWLING-UL!")
    else:
        log("✅ PASS: robots.txt permite crawling.")
except urllib.error.HTTPError as e:
    log(f"⚠️ robots.txt nu exista (HTTP {e.code})")
except Exception as e:
    log(f"⚠️ robots.txt error: {e}")

# Acum verificam si SUPERPARTY si WOWPARTY rapid
log("\n" + "=" * 80)
log("BONUS — VERIFICARE RAPIDA SUPERPARTY + WOWPARTY")
log("=" * 80)

for domain, url in [("SUPERPARTY", "https://www.superparty.ro/animatori-petreceri-copii"), 
                     ("WOWPARTY", "https://www.wowparty.ro/")]:
    log(f"\n--- {domain}: {url} ---")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'curl/7.68.0'})
        resp = urllib.request.urlopen(req, context=ctx, timeout=15)
        html = resp.read().decode('utf-8', errors='ignore')
        log(f"Status: HTTP {resp.status} ✅")
        canonical = re.search(r'<link[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', html, re.I)
        if canonical:
            log(f"Canonical: {canonical.group(1)} ✅")
        else:
            log("Canonical: LIPSA ⚠️")
    except Exception as e:
        log(f"Error: {e} ❌")

# Sitemaps pt toate
log("\n--- SITEMAPS TOATE SITE-URILE ---")
for sm in ["https://www.superparty.ro/sitemap.xml", "https://www.wowparty.ro/sitemap.xml"]:
    try:
        req = urllib.request.Request(sm, headers={'User-Agent': 'curl/7.68.0'})
        resp = urllib.request.urlopen(req, context=ctx, timeout=10)
        content = resp.read().decode('utf-8', errors='ignore')
        count = content.count('<loc>')
        log(f"{sm} -> HTTP 200 ✅, {count} URL-uri")
    except Exception as e:
        log(f"{sm} -> EROARE: {e} ❌")

log("\n" + "=" * 80)
log("SFARSIT VERIFICARE P0. REZULTATELE SUNT SALVATE PE DESKTOP.")
log("=" * 80)

with open(output, 'w', encoding='utf-8') as f:
    f.write("\n".join(lines))

print(f"\nFisier salvat: {output}")
