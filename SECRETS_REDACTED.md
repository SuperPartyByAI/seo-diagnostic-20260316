# Secrete Redactate

## Ce a fost redactat

Următoarele secrete au fost identificate și **NU** au fost incluse în repository:

### 1. `GSC_SERVICE_ACCOUNT_JSON`
- **Locație originală:** `C:\Users\ursac\Superparty\.env`
- **Tip:** Google Cloud Service Account JSON key
- **Email SA:** `superparty-seo-agent@gen-lang-client-0203593088.iam.gserviceaccount.com`
- **Folosit de:** Toate scripturile din `src/` care interacționează cu Google Search Console API

### Cum să restaurezi

1. Copiază fișierul `.env` din `C:\Users\ursac\Superparty\.env` în directorul rădăcină al proiectului.
2. Sau setează variabila de mediu `GSC_SERVICE_ACCOUNT_JSON` cu conținutul JSON al service account-ului.
3. Scripturile vor citi automat din `.env` la path-ul hardcodat `C:\Users\ursac\Superparty\.env`.
