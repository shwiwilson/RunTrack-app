// Read-only release/PWA layout smoke. No account or athlete data is created.
const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const origin = process.env.RUNTRACK_SMOKE_URL || 'http://localhost:3000';
assert.ok(['localhost', '127.0.0.1'].includes(new URL(origin).hostname),
  'This smoke test is restricted to a local release server.');

async function enableSemantics(page) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate(element => element.click());
    const tree = await page.locator('body').ariaSnapshot();
    if (tree.includes('RUNTRACK')) return tree;
    await page.waitForTimeout(100);
  }
  throw new Error('RunTrack did not render its welcome/setup surface.');
}

(async () => {
  fs.mkdirSync('test-results', {recursive: true});
  const browser = await chromium.launch({headless: true});
  const results = [];
  try {
    for (const viewport of [{width: 1280, height: 900}, {width: 390, height: 844}]) {
      const context = await browser.newContext({viewport});
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(origin);
      const tree = await enableSemantics(page);
      assert.ok(tree.includes('Getting RunTrack ready.') || tree.includes('Your running. Your club.'));
      const manifest = await page.evaluate(async () => (await fetch('manifest.json')).json());
      assert.equal(manifest.name, 'RunTrack');
      assert.equal(manifest.display, 'standalone');
      assert.equal(manifest.icons.length, 4);
      await page.screenshot({path: `test-results/release-${viewport.width}.png`});
      if (await page.getByRole('button', {name: 'Create account', exact: true}).count()) {
        await page.getByRole('button', {name: 'Create account', exact: true}).click();
        await page.getByRole('textbox', {name: 'Your name', exact: true}).waitFor();
        await page.screenshot({path: `test-results/registration-${viewport.width}.png`});
      }
      assert.deepEqual(errors, []);
      results.push({viewport, passed: true});
      await context.close();
    }
    fs.writeFileSync('test-results/release-smoke.json', JSON.stringify(results, null, 2));
    console.log('PASS desktop/mobile release surface, registration layout where configured, PWA manifest and browser runtime');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
