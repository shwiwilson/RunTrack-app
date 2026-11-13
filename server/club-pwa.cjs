const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const colourPattern = /^#[\da-f]{6}$/i;
const iconSizes = {
  'apple-touch-icon.png': 180,
  'icon-192.png': 192,
  'icon-512.png': 512,
  'maskable-192.png': 192,
  'maskable-512.png': 512,
};
const genericIcon = path.resolve(__dirname, '../web/icons/Icon-512.png');
const shellTemplate = path.resolve(__dirname, '../web/index.html');

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

function publicKey(config) {
  const key = config.SUPABASE_PUBLISHABLE_KEY?.trim() || config.SUPABASE_ANON_KEY?.trim() || '';
  if (key.startsWith('sb_publishable_')) return key;
  try {
    if (JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role === 'anon') return key;
  } catch {}
  throw new Error('A Supabase public key is required');
}

async function fetchBranding(slug, includeLogo, config, fetcher) {
  const endpoint = new URL('/rest/v1/rpc/club_install_branding', config.SUPABASE_URL);
  const response = await fetcher(endpoint, {
    method: 'POST',
    headers: { apikey: publicKey(config), 'content-type': 'application/json' },
    body: JSON.stringify({ p_slug: slug, p_include_logo: includeLogo }),
    signal: AbortSignal.timeout(4500),
    redirect: 'error',
  });
  if (!response.ok) throw new Error('Club branding lookup failed');
  return response.json();
}

function branding(row, slug) {
  if (row === null) return null;
  if (row?.slug !== slug || typeof row.name !== 'string' || !row.name.trim()) {
    throw new Error('Unexpected club branding response');
  }
  return {
    slug,
    name: row.name.trim().slice(0, 120),
    primary: colourPattern.test(row.primary) ? row.primary : '#315A18',
    background: colourPattern.test(row.background) ? row.background : '#F5F7F2',
    revision: /^[\da-f]{32}$/.test(row.revision) ? row.revision : '',
    logo: typeof row.logo === 'string' && row.logo.length <= 710000 ? row.logo : null,
  };
}

function clubPath(club) {
  return '/club/' + club.slug;
}

function iconPath(club, asset) {
  return clubPath(club) + '/' + asset + (club.revision ? '?v=' + club.revision : '');
}

function manifest(club) {
  const start = clubPath(club) + '/app';
  return {
    id: clubPath(club) + '/',
    name: club.name,
    short_name: club.name,
    start_url: start,
    scope: '/',
    display: 'standalone',
    background_color: club.background,
    theme_color: club.primary,
    icons: Object.entries(iconSizes).filter(([, size]) => size !== 180).map(([asset, size]) => ({
      src: iconPath(club, asset),
      sizes: size + 'x' + size,
      type: 'image/png',
      purpose: asset.startsWith('maskable') ? 'maskable' : 'any',
    })),
  };
}

async function renderIcon(club, asset) {
  const size = iconSizes[asset];
  // A square at 56% fits completely within the maskable safe circle.
  const logoSize = Math.floor(size * (asset.startsWith('maskable') ? 0.56 : 0.84));
  let logo;
  if (club?.logo) {
    try {
      const source = sharp(Buffer.from(club.logo, 'base64'), { limitInputPixels: 512 * 512, failOn: 'warning' });
      const metadata = await source.metadata();
      if (metadata.format !== 'png' || (metadata.pages ?? 1) !== 1) throw new Error('Expected a PNG');
      logo = await source.resize(logoSize, logoSize, { fit: 'inside' }).png().toBuffer();
    } catch {
      // Invalid or legacy artwork uses the generic icon.
    }
  }
  logo ??= await sharp(await fs.readFile(genericIcon)).resize(logoSize, logoSize).png().toBuffer();
  return sharp({
    create: { width: size, height: size, channels: 3, background: club?.background ?? '#F5F7F2' },
  }).composite([{ input: logo, gravity: 'centre' }]).removeAlpha().png().toBuffer();
}

function installPage(club, unavailable = false) {
  const name = club ? escapeHtml(club.name) : 'RunTrack';
  const launch = club ? clubPath(club) + '/app' : '/';
  const icon = club ? iconPath(club, 'apple-touch-icon.png') : '/icons/Icon-192.png';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="${club?.primary ?? '#315A18'}">
${club ? `<meta name="apple-mobile-web-app-title" content="${name}">
<meta name="mobile-web-app-capable" content="yes">
<link rel="manifest" href="${clubPath(club)}/manifest.webmanifest">
<link rel="apple-touch-icon" sizes="180x180" href="${icon}">
<link rel="icon" href="${icon}">
<script src="/club-install.js" defer></script>` : ''}
<link rel="stylesheet" href="/club-install.css">
<title>${club ? 'Install ' + name : 'Club installation · RunTrack'}</title>
</head>
<body>
<main>
${club ? `<img src="${icon}" width="80" height="80" alt="">
<h1>Install ${name}</h1>
<p>Open RunTrack from your home screen with your club’s name and badge.</p>
<button id="install" type="button" hidden>Install app</button>
<p id="install-status" role="status"></p>
<section aria-label="Installation instructions">
<p data-platform="ios"><strong>iPhone or iPad:</strong> Open this page in Safari, tap Share, then Add to Home Screen. If offered, turn on Open as Web App and tap Add.</p>
<p data-platform="android"><strong>Android:</strong> In Chrome, open the menu and tap Install app or Add to Home screen. In Samsung Internet, tap the install icon or use Menu → Add page to → Home screen.</p>
<p data-platform="desktop"><strong>Computer:</strong> Use the install icon in Chrome or Edge, or File → Add to Dock in Safari on supported Macs. If your browser has no install option, open this link in a supported browser.</p>
</section>
<details><summary>Replacing an existing RunTrack shortcut?</summary>
<p>Remove or uninstall the old shortcut using your device’s menu, then reopen this link in your browser and install again. Your account and synced runs stay in RunTrack. You may need to sign in again.</p>
</details>` : `<h1>${unavailable ? 'Club branding is temporarily unavailable' : 'Club installation unavailable'}</h1>
<p>${unavailable ? 'Reload this page to try again.' : 'Check the link with your club or open RunTrack to find your active club.'}</p>`}
<a id="open-runtrack" href="${launch}">Open RunTrack</a>
<a class="privacy" href="/privacy.html">Privacy</a>
</main>
</body>
</html>`;
}

async function appPage(club) {
  const name = escapeHtml(club.name);
  const badge = iconPath(club, 'apple-touch-icon.png');
  const source = await fs.readFile(shellTemplate, 'utf8');
  return source
    .replace('$FLUTTER_BASE_HREF', '/')
    .replace('<title>RunTrack</title>', () => '<title>' + name + '</title>')
    .replace('name="apple-mobile-web-app-title" content="RunTrack"', () =>
      'name="apple-mobile-web-app-title" content="' + name + '"')
    .replace('name="theme-color" content="#315A18"', () =>
      'name="theme-color" content="' + club.primary + '"')
    .replace('rel="manifest" href="manifest.json"', () =>
      'rel="manifest" href="' + clubPath(club) + '/manifest.webmanifest"')
    .replace('rel="apple-touch-icon" href="icons/Icon-192.png"', () =>
      'rel="apple-touch-icon" sizes="180x180" href="' + badge + '"')
    .replace('rel="icon" type="image/png" href="favicon.png"', () =>
      'rel="icon" type="image/png" href="' + badge + '"');
}

function createHandler({ config = process.env, fetcher = fetch } = {}) {
  return async (req, res) => {
    const send = (status, type, body, cache = 'no-store') => {
      res.statusCode = status;
      res.setHeader('Content-Type', type);
      res.setHeader('Cache-Control', cache);
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.setHeader('Referrer-Policy', 'no-referrer');
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    const html = 'text/html; charset=utf-8';
    const json = 'application/json; charset=utf-8';
    if (!['GET', 'HEAD'].includes(req.method)) {
      res.setHeader('Allow', 'GET, HEAD');
      return send(405, json, '{"error":"Method not allowed"}');
    }
    const request = new URL(req.url, 'http://localhost');
    const route = /^\/club\/([^/]+)\/([^/]+)\/?$/.exec(request.pathname);
    const slug = route?.[1] ?? req.query?.slug ?? request.searchParams.get('slug');
    const asset = route?.[2] ?? req.query?.asset ?? request.searchParams.get('asset');
    const isIcon = typeof asset === 'string' && Object.hasOwn(iconSizes, asset);
    if (typeof slug !== 'string' || slug.length > 80 || !slugPattern.test(slug) ||
        !(asset === 'app' || asset === 'install' || asset === 'manifest.webmanifest' || isIcon)) {
      return send(404, html, installPage(null));
    }
    try {
      const club = branding(await fetchBranding(slug, isIcon, config, fetcher), slug);
      if (!club) {
        if (asset === 'app') {
          res.setHeader('Location', '/');
          return send(302, html, '');
        }
        return asset === 'install'
          ? send(404, html, installPage(null))
          : send(404, json, '{"error":"Club not available"}');
      }
      if (asset === 'app') return send(200, html, await appPage(club), 'no-cache');
      if (asset === 'install') return send(200, html, installPage(club), 'no-cache');
      if (isIcon) return send(200, 'image/png', await renderIcon(club, asset), 'public, max-age=300');
      return send(200, 'application/manifest+json; charset=utf-8', JSON.stringify(manifest(club)), 'no-cache');
    } catch (error) {
      console.error('RunTrack club install:', error.name);
      return asset === 'install' || asset === 'app'
        ? send(503, html, installPage(null, true))
        : send(503, json, '{"error":"Club branding temporarily unavailable"}');
    }
  };
}

module.exports = { createHandler };
