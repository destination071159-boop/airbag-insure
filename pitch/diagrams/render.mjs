// Renders diagram.html to PNGs: node render.mjs  (uses airbag/demo-video's playwright)
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
const require = createRequire(new URL("../../demo-video/package.json", import.meta.url));
const { chromium } = require("playwright");

const here = fileURLToPath(new URL(".", import.meta.url));
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
for (const [d, w, h] of [["concept", 940, 790], ["full", 1400, 1000], ["depeg", 940, 790], ["depeg-full", 1400, 1000]]) {
  await page.setViewportSize({ width: w, height: h });
  await page.goto(`file://${here}diagram.html?d=${d}`);
  await page.waitForSelector("body[data-ready]");
  await page.waitForTimeout(300);
  await page.locator("#stage").screenshot({ path: `${here}airbag-${d.startsWith("depeg") ? d : "lp-" + d}.png` });
  console.log(`wrote ${d}`);
}
await browser.close();
