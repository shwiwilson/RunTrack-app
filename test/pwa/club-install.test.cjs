const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const sharp = require('sharp');
const { createHandler } = require('../../server/club-pwa.cjs');

let server;
let base;
let png;
const calls = [];
let offline = false;
const club = {
  slug: 'tyne-bridge-harriers',
  name: 'Tyne Bridge Harriers',
  primary: '#FFFFFF',
  background: '#111111',
  revision: '1'.repeat(32),
};

before(async () => {
  png = await sharp({
    create: { width: 80, height: 40, channels: 4, background: '#FF0000' },
  }).png().toBuffer();
  const handler = createHandler({
    config: { SUPABASE_URL: 'https://db.example.test', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_fixture' },
    fetcher: async (url, options) => {
      const input = JSON.parse(options.body);
      calls.push({ url, options, input });
      if (offline) return new Response('', { status: 503 });
      const row = {
        [club.slug]: { ...club, logo: input.p_include_logo ? png.toString('base64') : null },
        'another-club': {
          ...club, slug: 'another-club', name: '<script>alert("club")</script>',
          primary: 'invalid', background: 'invalid', logo: 'invalid',
        },
      }[input.p_slug];
      return Response.json(row ?? null);
    },
  });
  server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
});

after(async () => {
  await new Promise(resolve => server.close(resolve));
});

test('install page declares a real manifest and Apple touch icon in the initial HTML', async () => {
  const page = await fetch(base + '/club/' + club.slug + '/install');
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /href="\/club\/tyne-bridge-harriers\/manifest.webmanifest"/);
  assert.match(html, /apple-touch-icon" sizes="180x180" href="\/club\/tyne-bridge-harriers\/apple-touch-icon.png\?v=/);
  assert.match(html, /apple-mobile-web-app-title" content="Tyne Bridge Harriers"/);
  assert.match(html, /href="\/club\/tyne-bridge-harriers\/app"/);
  assert.match(html, /Samsung Internet/);
  assert.match(html, /Replacing an existing RunTrack shortcut/);
  assert.equal(calls.at(-1).input.p_include_logo, false);
  assert.equal(calls.at(-1).options.headers.apikey, 'sb_publishable_fixture');
});

test('club manifests have independent stable identities and valid install artwork', async () => {
  const response = await fetch(base + '/club/' + club.slug + '/manifest.webmanifest');
  assert.match(response.headers.get('content-type'), /^application\/manifest\+json/);
  const manifest = await response.json();
  assert.equal(manifest.id, '/club/tyne-bridge-harriers/');
  assert.equal(manifest.start_url, '/club/tyne-bridge-harriers/app');
  assert.equal(manifest.scope, '/');
  assert.equal(manifest.theme_color, '#FFFFFF');
  assert.equal(manifest.name, club.name);
  assert.equal(manifest.display, 'standalone');
  assert.equal(manifest.icons.length, 4);
  const icons = [...manifest.icons, { src: '/club/' + club.slug + '/apple-touch-icon.png', sizes: '180x180' }];
  for (const icon of icons) {
    const result = await fetch(base + icon.src);
    assert.equal(result.headers.get('content-type'), 'image/png');
    const image = sharp(Buffer.from(await result.arrayBuffer()));
    const { format, width, height, hasAlpha } = await image.metadata();
    assert.equal(format, 'png');
    assert.equal(width + 'x' + height, icon.sizes);
    assert.equal(hasAlpha, false);
    const centre = await image.clone().extract({ left: width / 2, top: height / 2, width: 1, height: 1 }).raw().toBuffer();
    assert.deepEqual([...centre], [255, 0, 0]);
    if (icon.purpose === 'maskable') {
      const edge = await image.extract({ left: 0, top: 0, width: 1, height: 1 }).raw().toBuffer();
      assert.deepEqual([...edge], [17, 17, 17]);
    }
    assert.equal(calls.at(-1).input.p_include_logo, true);
  }

  const other = await (await fetch(base + '/club/another-club/manifest.webmanifest')).json();
  assert.notEqual(other.id, manifest.id);
  assert.notEqual(other.start_url, manifest.start_url);
  assert.equal(other.theme_color, '#315A18');
  assert.equal(other.background_color, '#F5F7F2');
});

test('the installed start URL serves Flutter with the same manifest and icon', async () => {
  const response = await fetch(base + '/club/' + club.slug + '/app');
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<base href="\/">/);
  assert.match(html, /<title>Tyne Bridge Harriers<\/title>/);
  assert.match(html, /href="\/club\/tyne-bridge-harriers\/manifest.webmanifest"/);
  assert.match(html, /src="flutter_bootstrap.js"/);
  const fallback = await fetch(base + '/club/missing/app', { redirect: 'manual' });
  assert.equal(fallback.status, 302);
  assert.equal(fallback.headers.get('location'), '/');
});

test('invalid artwork uses a real fallback and names are safe in HTML', async () => {
  const page = await (await fetch(base + '/club/another-club/install')).text();
  assert.doesNotMatch(page, /<script>alert/);
  assert.match(page, /&lt;script&gt;alert\(&quot;club&quot;\)&lt;\/script&gt;/);
  const response = await fetch(base + '/club/another-club/apple-touch-icon.png');
  assert.equal(response.status, 200);
  const fallback = await sharp(Buffer.from(await response.arrayBuffer())).metadata();
  assert.equal(fallback.width, 180);
  assert.equal(fallback.format, 'png');
});

test('invalid, inactive or unavailable clubs never get a branded install prompt', async () => {
  const count = calls.length;
  assert.equal((await fetch(base + '/club/INVALID/install')).status, 404);
  assert.equal(calls.length, count);
  const missing = await fetch(base + '/club/missing/install');
  assert.equal(missing.status, 404);
  assert.doesNotMatch(await missing.text(), /rel="manifest"/);
  assert.equal((await fetch(base + '/club/missing/manifest.webmanifest')).status, 404);
  offline = true;
  try {
    const unavailable = await fetch(base + '/club/' + club.slug + '/install');
    assert.equal(unavailable.status, 503);
    assert.doesNotMatch(await unavailable.text(), /rel="manifest"/);
  } finally {
    offline = false;
  }
});
