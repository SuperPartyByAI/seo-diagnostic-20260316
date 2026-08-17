import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { chromium } from "playwright";

const baseURL = process.env.LM_GA4_BASE_URL || "http://127.0.0.1:43991";
const outputDir = process.env.LM_GA4_EVIDENCE_DIR || process.cwd();
const expectedId = "G-4C4JFDT4F2";

fs.mkdirSync(outputDir, { recursive: true });

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function exercise(viewport, label) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const googleRequests = [];
  const collectRequests = [];
  const consoleErrors = [];

  page.on("request", (request) => {
    const url = request.url();
    if (/googletagmanager\.com|google-analytics\.com/i.test(url)) {
      googleRequests.push(url);
    }
    if (/google-analytics\.com\/g\/collect/i.test(url)) {
      collectRequests.push(url);
    }
  });
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => consoleErrors.push(error.message));

  await page.goto(`${baseURL}/?ga4_debug=1&qa=${label}`, {
    waitUntil: "networkidle",
    timeout: 60000,
  });

  assert(await page.locator("#lm-analytics-consent").isVisible(), `${label}: banner missing`);
  assert(googleRequests.length === 0, `${label}: Google request before consent: ${googleRequests.join(" | ")}`);
  assert(
    (await page.locator('script[src*="googletagmanager.com/gtag/js"]').count()) === 0,
    `${label}: gtag script exists before consent`,
  );

  await page.screenshot({
    path: path.join(outputDir, `${label}-consent-before.png`),
    fullPage: true,
  });

  await page.locator('[data-lm-consent="granted"]').click();
  await page.waitForFunction(() => window.localStorage.getItem("lm_analytics_consent_v1")?.includes("granted"));
  await page.waitForRequest((request) => request.url().includes(`googletagmanager.com/gtag/js?id=${expectedId}`), {
    timeout: 30000,
  }).catch(() => null);
  await page.waitForTimeout(2500);

  const scriptCount = await page.locator(`script[data-lm-ga4="${expectedId}"]`).count();
  assert(scriptCount === 1, `${label}: expected one Google tag script, got ${scriptCount}`);
  assert(
    googleRequests.some((url) => url.includes(expectedId)),
    `${label}: expected measurement ID request missing`,
  );
  assert(
    googleRequests.every((url) => !url.includes("G-5JWGETTK8S") && !url.includes("549983021")),
    `${label}: Time4Pizza identifier leaked`,
  );

  const queuedBefore = await page.evaluate(() => window.dataLayer?.length || 0);
  await page.evaluate(() => {
    const phone = document.querySelector('a[href^="tel:"]');
    if (phone) phone.addEventListener("click", (event) => event.preventDefault(), { once: true });
  });
  const phone = page.locator('a[href^="tel:"]').first();
  if (await phone.count()) await phone.click();

  await page.evaluate(() => {
    const wa = document.querySelector('a[href*="wa.me"], a[href*="whatsapp.com"]');
    if (wa) wa.addEventListener("click", (event) => event.preventDefault(), { once: true });
  });
  const whatsapp = page.locator('a[href*="wa.me"], a[href*="whatsapp.com"]').first();
  if (await whatsapp.count()) await whatsapp.click();
  await page.waitForTimeout(1200);

  const queued = await page.evaluate(() =>
    (window.dataLayer || []).map((entry) => {
      if (entry && typeof entry === "object" && "0" in entry) {
        return Array.from(entry);
      }
      return entry;
    }),
  );
  const serialized = JSON.stringify(queued);
  assert(serialized.includes("phone_click"), `${label}: phone_click missing`);
  assert(serialized.includes("whatsapp_click"), `${label}: whatsapp_click missing`);
  assert(serialized.includes("generate_lead"), `${label}: generate_lead missing`);
  assert(!serialized.includes("0722816161"), `${label}: raw phone number leaked into event payload`);
  assert((await page.evaluate(() => window.dataLayer?.length || 0)) > queuedBefore, `${label}: event queue did not grow`);

  const width = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  assert(width.scrollWidth <= width.clientWidth + 1, `${label}: horizontal overflow ${JSON.stringify(width)}`);

  await page.screenshot({
    path: path.join(outputDir, `${label}-after-consent.png`),
    fullPage: true,
  });

  const rejectContext = await browser.newContext({ viewport });
  const rejectPage = await rejectContext.newPage();
  const rejectGoogleRequests = [];
  rejectPage.on("request", (request) => {
    if (/googletagmanager\.com|google-analytics\.com/i.test(request.url())) {
      rejectGoogleRequests.push(request.url());
    }
  });
  await rejectPage.goto(`${baseURL}/?qa=${label}-deny`, { waitUntil: "networkidle", timeout: 60000 });
  await rejectPage.locator('[data-lm-consent="denied"]').click();
  await rejectPage.waitForTimeout(1500);
  assert(rejectGoogleRequests.length === 0, `${label}: Google request after denial: ${rejectGoogleRequests.join(" | ")}`);
  assert(
    (await rejectPage.evaluate(() => localStorage.getItem("lm_analytics_consent_v1")))?.includes("denied"),
    `${label}: denied choice not persisted`,
  );

  await rejectContext.close();
  await context.close();
  await browser.close();

  return {
    label,
    viewport,
    googleRequests,
    collectRequestCount: collectRequests.length,
    consoleErrors,
    width,
  };
}

const results = [];
results.push(await exercise({ width: 1440, height: 1000 }, "desktop-1440x1000"));
results.push(await exercise({ width: 390, height: 844 }, "mobile-390x844"));

fs.writeFileSync(
  path.join(outputDir, "playwright-results.json"),
  JSON.stringify({ expectedId, baseURL, checkedAt: new Date().toISOString(), results }, null, 2),
);

if (results.some((result) => result.consoleErrors.length > 0)) {
  throw new Error(`console errors: ${JSON.stringify(results.map((result) => result.consoleErrors))}`);
}

console.log(JSON.stringify({ status: "PASS", expectedId, results }, null, 2));
