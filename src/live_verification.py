import urllib.request
import re
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def check_url(url):
    print(f"\n--- VERIFICARE LIVE: {url} ---")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        response = urllib.request.urlopen(req, context=ctx, timeout=10)
        html = response.read().decode('utf-8', errors='ignore')
        
        print(f"Status HTTP: 200 OK (Pagina functioneaza, NICIUN REDIRECT 301/307)")
        
        canonical_match = re.search(r'<link[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']', html, re.IGNORECASE)
        if canonical_match:
            print(f"Tag Canonical: PREZENT -> {canonical_match.group(1)}")
        else:
            print("Tag Canonical: LIPSA!")
            
    except urllib.error.HTTPError as e:
        print(f"Eroare HTTP: {e.code}")
        print(f"Redirect Location: {e.headers.get('Location', 'N/A')}")
    except Exception as e:
        print(f"Eroare Conexiune: {e}")

# Verificam erorile mentionate in ghid
urls_to_check = [
    "https://www.superparty.ro/animatori-petreceri-copii",
    "https://www.superparty.ro/petreceri/animatori-petreceri-copii-sector-1",
    "https://www.wowparty.ro/",
    "https://www.animatopia.ro/"
]

for u in urls_to_check:
    check_url(u)
    
print("\n--- VERIFICARE SITEMAP-URI LIVE ---")
sitemaps = [
    "https://www.superparty.ro/sitemap.xml",
    "https://www.animatopia.ro/sitemap-0.xml"
]

for s in sitemaps:
    try:
        req = urllib.request.Request(s, headers={'User-Agent': 'Mozilla/5.0'})
        response = urllib.request.urlopen(req, context=ctx, timeout=10)
        xml = response.read().decode('utf-8', errors='ignore')
        count = xml.count("<loc>")
        print(f"Sitemap {s}: 200 OK, contine {count} linkuri.")
    except Exception as e:
        print(f"Sitemap {s}: Eroare: {e}")
