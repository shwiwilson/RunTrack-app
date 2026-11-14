const assert = require('node:assert/strict');
const { chromium } = require('playwright');

async function main() {
  const base = process.env.RUNTRACK_TEST_URL || 'http://127.0.0.1:3000';
  const slug = process.env.RUNTRACK_TEST_CLUB || 'tyne-bridge-harriers';
  const install = '/club/' + slug + '/install';
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  try {
    const desktop = await browser.newContext();
    const page = await desktop.newPage();
    assert.equal((await page.goto(base + install)).status(), 200);
    await page.locator('[data-platform=desktop]').waitFor({ state: 'visible' });
    const client = await desktop.newCDPSession(page);
    const inspected = await client.send('Page.getAppManifest');
    const manifest = JSON.parse(inspected.data);
    assert.equal(new URL(inspected.url).pathname, '/club/' + slug + '/manifest.webmanifest');
    assert.equal(manifest.start_url, '/club/' + slug + '/app');
    assert.equal(manifest.display, 'standalone');
    assert.deepEqual(inspected.errors, []);
    const { installabilityErrors } = await client.send('Page.getInstallabilityErrors');
    assert.deepEqual(installabilityErrors, []);
    const installArtwork = page.locator('main img');
    await installArtwork.evaluate(image => image.decode());
    assert.equal(await installArtwork.evaluate(image => image.naturalWidth), 180);
    await page.getByText('Replacing an existing RunTrack shortcut?').click();
    await page.getByText('Remove or uninstall the old shortcut', { exact: false }).waitFor();
    await page.locator('#open-runtrack').click();
    await page.waitForURL(base + manifest.start_url);
    assert.equal(await page.locator('link[rel=manifest]').getAttribute('href'), '/club/' + slug + '/manifest.webmanifest');
    await page.waitForFunction(() => !document.getElementById('opening'), null, { timeout: 30000 });
    const root = await page.goto(base);
    assert.equal(root.status(), 200);
    assert.equal(await page.locator('link[rel=manifest]').getAttribute('href'), 'manifest.json');
    const generic = await (await desktop.request.get(base + '/manifest.json')).json();
    assert.equal(generic.name, 'RunTrack');
    assert.notEqual(generic.id, manifest.id);

    const platforms = [
      ['ios', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Version/18.6 Mobile/15E148 Safari/604.1'],
      ['android', 'Mozilla/5.0 (Linux; Android 15; SAMSUNG SM-S938B) AppleWebKit/537.36 SamsungBrowser/28.0 Chrome/130.0.0.0 Mobile Safari/537.36'],
    ];
    for (const [platform, userAgent] of platforms) {
      const context = await browser.newContext({ userAgent, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
      const mobile = await context.newPage();
      await mobile.goto(base + install);
      await mobile.locator('[data-platform=' + platform + ']').waitFor({ state: 'visible' });
      assert.equal(await mobile.locator('[data-platform=desktop]').isVisible(), false);
      await context.close();
    }
    console.log('Chromium installability, manifest, artwork, launch, generic fallback and mobile instructions passed.');
  } finally {
    await browser.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
