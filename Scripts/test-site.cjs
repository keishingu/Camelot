// Browser smoke check. Requires Node.js, Playwright, and its Chromium browser.
// Run: node Scripts/test-site.cjs (or set NODE_PATH to an existing Playwright installation).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../docs/site');
const output = path.resolve(__dirname, '../.build/site-preview');
const server = http.createServer((req, res) => {
  const file = path.resolve(root, `.${decodeURIComponent(new URL(req.url, 'http://localhost').pathname)}`);
  if (!file.startsWith(`${root}/`) && file !== root) { res.writeHead(403).end(); return; }
  const target = file === root ? path.join(root, 'index.html') : file;
  fs.readFile(target, (error, data) => {
    if (error) { res.writeHead(404).end(); return; }
    res.setHeader('Content-Type', ({ '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' })[path.extname(target)] || 'application/octet-stream');
    res.end(data);
  });
});

(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, colorScheme: 'light' });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(origin);
    const demo = page.locator('#demo');
    await demo.focus();
    await page.keyboard.press('Alt');
    assert.equal(await demo.getAttribute('data-state'), 'hints', 'Option tap starts hints');
    await page.keyboard.press('s');
    assert.equal(await page.locator('[data-prefix]').textContent(), 'S');
    await page.keyboard.press('x');
    assert.equal(await page.locator('[data-prefix]').textContent(), 'S', 'invalid input retains prefix');
    await page.keyboard.press('Backspace');
    await page.keyboard.press('s');
    await page.keyboard.press('d');
    assert.match(await page.locator('[data-status]').textContent(), /Save/);
    await page.locator('[data-demo-key="option"]').click();
    await page.keyboard.press('f');
    assert.equal(await page.locator('#demo-name').evaluate((el) => document.activeElement === el), true, 'F focuses input');
    await page.keyboard.type('Camelot');
    assert.equal(await page.locator('#demo-name').inputValue(), 'Camelot');
    await page.locator('[data-demo-key="option"]').click();
    await page.keyboard.press('Escape');
    assert.equal(await demo.getAttribute('data-state'), 'idle');
    await page.keyboard.down('Alt');
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.up('Alt');
    assert.equal(await demo.getAttribute('data-state'), 'idle', 'Option chord is not a tap');
    await page.locator('[data-demo-key="option"]').click();
    await page.locator('header .brand').focus();
    assert.equal(await demo.getAttribute('data-state'), 'idle', 'leaving demo cancels hints');
    await page.keyboard.press('Alt');
    assert.equal(await demo.getAttribute('data-state'), 'idle', 'outside keys do not start demo');
    const checkbox = page.locator('[data-hint="A"] input');
    const checkedBefore = await checkbox.isChecked();
    await page.locator('[data-demo-key="option"]').click();
    await checkbox.click();
    assert.equal(await checkbox.isChecked(), !checkedBefore, 'pointer cancels hints and toggles checkbox once');
    assert.equal(await demo.getAttribute('data-state'), 'idle');
    assert.equal(await page.locator('[data-cta][href]').count(), 0, 'prelaunch does not expose a download');

    fs.mkdirSync(output, { recursive: true });
    for (const [name, width, scheme] of [['desktop', 1440, 'light'], ['mobile', 390, 'light'], ['dark', 1440, 'dark']]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.emulateMedia({ colorScheme: scheme, reducedMotion: 'reduce' });
      for (const url of ['/', '/support.html', '/privacy.html']) {
        assert.equal((await page.goto(`${origin}${url}`)).status(), 200);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true, `${name} ${url}: horizontal overflow`);
        for (const href of await page.locator('a[href]').evaluateAll((links) => links.map((a) => a.getAttribute('href')))) {
          const target = new URL(href, page.url());
          if (target.origin === origin && !target.hash) assert.equal((await page.request.get(target.href)).status(), 200, `broken link ${href}`);
        }
        if (url === '/') {
          await page.locator('[data-demo-key="option"]').click();
          if (width === 390) {
            await page.locator('[data-demo-key="S"]').click();
            await page.locator('[data-demo-key="D"]').click();
            assert.match(await page.locator('[data-status]').textContent(), /Save/);
            await page.locator('[data-demo-key="option"]').click();
          }
          await page.evaluate(() => window.scrollTo(0, 0));
          await page.screenshot({ path: path.join(output, `${name}.png`), fullPage: true });
        }
      }
    }
    const liveScript = fs.readFileSync(path.join(root, 'assets/site.js'), 'utf8')
      .replace('available: false', 'available: true').replace('dmgUrl: ""', 'dmgUrl: "https://example.invalid/Camelot.dmg"');
    await page.route('**/assets/site.js', (route) => route.fulfill({ contentType: 'text/javascript', body: liveScript }));
    await page.goto(origin);
    assert.equal(await page.locator('[data-cta][href="https://example.invalid/Camelot.dmg"]').count(), 2, 'release configuration enables both download links');
    assert.equal(await page.locator('[data-cta][aria-disabled]').count(), 0);
    assert.doesNotMatch(await page.locator('#download-title').textContent(), /準備/);
    assert.deepEqual(errors, []);
    console.log('Site smoke checks passed: keyboard, focus, touch, prelaunch links, responsive pages, light/dark.');
  } finally {
    if (browser) await browser.close();
    server.close();
  }
})().catch((error) => { console.error(error); server.close(); process.exitCode = 1; });
