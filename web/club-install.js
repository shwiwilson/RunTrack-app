const installButton = document.getElementById('install');
const status = document.getElementById('install-status');
const openLink = document.getElementById('open-runtrack');
const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
const ios = /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const platform = ios ? 'ios' : /Android/i.test(navigator.userAgent) ? 'android' : 'desktop';

if (standalone) {
  // Some browsers save the install page itself when making a shortcut.
  if (openLink) window.location.replace(openLink.href);
} else {
  for (const step of document.querySelectorAll('[data-platform]')) {
    step.hidden = step.dataset.platform !== platform;
  }
  let prompt;
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    prompt = event;
    installButton.hidden = false;
  });
  installButton.addEventListener('click', async () => {
    if (!prompt) return;
    const current = prompt;
    prompt = null;
    installButton.hidden = true;
    try {
      const result = await current.prompt();
      if (result.outcome === 'accepted') status.textContent = 'Check your home screen or app list.';
    } catch {
      status.textContent = 'Use your browser’s install option below.';
    }
  });
  window.addEventListener('appinstalled', () => {
    prompt = null;
    installButton.hidden = true;
    status.textContent = 'Installed. Open the app from your home screen or app list.';
  });
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
}
