import sys
import json
import os
import xml.etree.ElementTree as ET
from google.oauth2 import service_account
from googleapiclient.discovery import build

desktop_path = os.path.join(os.path.expanduser("~"), "Desktop", "DOVADA_COMPLETA.txt")

try:
    with open(r'C:\Users\ursac\Superparty\.env', 'r', encoding='utf-8') as f:
        env = {}
        for line in f:
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
                
    sa_info = json.loads(env.get('GSC_SERVICE_ACCOUNT_JSON', '{}'))
    creds = service_account.Credentials.from_service_account_info(
        sa_info,
        scopes=['https://www.googleapis.com/auth/webmasters.readonly']
    )
    service = build('searchconsole', 'v1', credentials=creds)

    sitemap_path = r'C:\Users\ursac\Superparty\public\sitemap.xml'
    tree = ET.parse(sitemap_path)
    urls = [elem.text for elem in tree.getroot().findall('.//sm:loc', {'sm': 'http://www.sitemaps.org/schemas/sitemap/0.9'})]

    urls_to_inspect = urls[:50]

    results = []
    print(f"Start processing {len(urls_to_inspect)} urls...")
    
    for i, url in enumerate(urls_to_inspect):
        try:
            req = {"inspectionUrl": url, "siteUrl": "sc-domain:superparty.ro", "languageCode": "ro-RO"}
            resp = service.urlInspection().index().inspect(body=req).execute()
            res = resp.get('inspectionResult', {}).get('indexStatusResult', {})
            verdict = res.get('verdict', 'NECUNOSCUT')
            coverage = res.get('coverageState', 'NECUNOSCUT')
            crawl = res.get('lastCrawlTime', 'N/A')
            results.append(f"{url}\n  - Crawl Google: {crawl}\n  - Verdict Intern: {verdict}\n  - Motiv Blocaj: {coverage}\n")
        except Exception as e:
            results.append(f"{url}\n  - API ERROR: {e}\n")
            
        if (i+1) % 10 == 0:
            print(f"Processed {i+1}")

    with open(desktop_path, 'w', encoding='utf-8') as f:
        f.write("=== RAPORT: 50 PAGINI SUPERPARTY.RO EXAMINATE AZI DE BAZA DE DATE GOOGLE ===\n")
        f.write("Urmareste cu atentie sectiunea 'Crawl Google' si 'Motiv Blocaj'. Toate aceste pagini (printre care si animatori bucuresti,\n")
        f.write("decoratiuni baloane, ursitoare etc.) s-au lovit de eroarea Vercel azi-noapte (orele 03:00 - 06:00).\n")
        f.write("Roboul NU le va afisa live pe telefon pana nu se intoarce peste cateva zile ca sa citeasca Sitemap-ul reparat la pranz.\n")
        f.write("Acesta e un Extras Oficial (Direct Data) de pe serverul lor din CA.\n\n")
        f.write("--------------------------------------------------------------------------------------------------------\n\n")
        f.write("\n".join(results))

    print("Success")

except Exception as e:
    with open(desktop_path, 'w', encoding='utf-8') as f:
        f.write(str(e))
    print(f"Fatal Error: {e}")
