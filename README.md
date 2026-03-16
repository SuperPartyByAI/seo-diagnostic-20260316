# SEO Diagnostic & Fix — 16 Martie 2026

Acest repository conține toate scripturile și rezultatele generate în sesiunea de diagnostic SEO pentru site-urile **superparty.ro**, **animatopia.ro** și **wowparty.ro**.

## Problema Rezolvată

1. **Redirect Loop Fatal** — `vercel.json` conținea o regulă `/(.*) → https://www.superparty.ro/$1` care crea o buclă infinită de redirect 307, cauzând de-indexarea completă de către Google.
2. **Cross-Domain Contamination** — Domeniul `animatopia.ro` era legat de proiectul Vercel al Superparty, servind conținut, canonical și titlu greșite.
3. **Sitemap Lipsă** — Modulul `@astrojs/sitemap` picase pe Vercel; generat manual cu Python (510 URL-uri).
4. **GSC Ownership Wowparty** — Service Account-ul nu avea acces pe proprietatea Wowparty (403).

## Structura Fișierelor

### `src/` — Scripturi Python
| Fișier | Descriere |
|--------|-----------|
| `extrage_dovada_singura.py` | Extrage date GSC URL Inspection API pentru un singur URL |
| `extrage_dovada_50urls.py` | Extrage date GSC pentru 50 URL-uri (sincron) |
| `extrage_dovada_toate_siteurile.py` | Extrage date GSC pentru toate URL-urile din sitemaps (3 domenii) |
| `gsc_submit_sitemaps.py` | Trimite sitemaps la Google Search Console via API |
| `duplicate_scan.py` | Scanare duplicate content pe 499 articole Superparty |
| `diagnostic_216urls.py` | Diagnostic complet READ-ONLY pe 216 URL-uri din GSC |
| `check_urls_full.py` | Diagnostic complet multi-domeniu cu JSON output |
| `p0_animatopia_verify.py` | Verificare P0 Animatopia (redirect, canonical, sitemap, robots) |
| `live_verification.py` | Verificare live HTTP headers și canonical tags |

### `docs/` — Rezultate
| Fișier | Descriere |
|--------|-----------|
| `GSC_DIAGNOSTIC_216_URLS.json` | Rezultat complet al diagnosticului pe 216 URL-uri |
| `urls_gsc_216.txt` | Lista celor 216 URL-uri Superparty din Google Search Console |

### `meta/`
| Fișier | Descriere |
|--------|-----------|
| `upload-manifest.json` | Manifest cu lista fișierelor și mapping la conversație |

## Dependențe

```bash
pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib requests
```

## Secrete

⚠️ Scripturile necesită `GSC_SERVICE_ACCOUNT_JSON` din fișierul `.env`. Acesta **NU** a fost comis — vezi `SECRETS_REDACTED.md`.

## Licență

MIT
