(() => {
  'use strict';
  const $ = (selector) => document.querySelector(selector);
  const source = $('#source');
  const output = $('#output');
  const status = $('#status');
  const tokenInput = $('#token');
  const TOKEN_KEY = 'luaPastefy.apiToken';
  const SHARE_CACHE = 'lua-paste-share-v1';
  const SHARE_KEY = new URL('/__lua_share_payload__', location.origin).href;

  function setStatus(message, kind = '') {
    status.textContent = message;
    status.className = `status ${kind}`.trim();
  }
  function updateLength() { $('#length').textContent = `${source.value.length.toLocaleString('de-DE')} Zeichen`; }
  function getToken() { return localStorage.getItem(TOKEN_KEY) || ''; }
  function makeLoadstring(id) { return `loadstring(game:HttpGet("https://pastefy.app/${id}/raw"))()`; }
  function extractId(data) {
    const candidate = data?.paste?.id || data?.id || data?.paste_id;
    if (typeof candidate !== 'string' || !/^[A-Za-z0-9_-]+$/.test(candidate)) throw new Error('Pastefy hat keine gültige Paste-ID zurückgegeben.');
    return candidate;
  }

  async function upload() {
    const code = source.value;
    if (!code.trim()) { setStatus('Bitte zuerst Lua-Code einfügen oder teilen.', 'error'); source.focus(); return; }
    const token = getToken();
    if (!token) {
      setStatus('Bitte speichere zuerst deinen Pastefy-API-Token in den Einstellungen. Der Code bleibt hier erhalten.', 'error');
      $('#settings').open = true;
      tokenInput.focus();
      return;
    }
    $('#convert').disabled = true;
    output.value = '';
    setStatus('Lua-Code wird sicher an Pastefy übertragen…');
    try {
      const response = await fetch('https://pastefy.app/api/v2/paste', {
        method: 'POST',
        mode: 'cors',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ title: 'Lua script', content: code, visibility: 'UNLISTED', type: 'PASTE' })
      });
      const raw = await response.text();
      let data;
      try { data = JSON.parse(raw); } catch { data = {}; }
      if (!response.ok) {
        const detail = data?.message || data?.error || `HTTP ${response.status}`;
        throw new Error(`Pastefy-Upload fehlgeschlagen (${detail}). Token prüfen und erneut versuchen.`);
      }
      const id = extractId(data);
      output.value = makeLoadstring(id);
      setStatus('Paste erstellt. Der Loadstring ist bereit zum Kopieren.', 'ok');
      output.focus();
      output.select();
    } catch (error) {
      const message = error instanceof TypeError ? 'Pastefy ist nicht erreichbar oder der Browser blockiert die Verbindung (Netzwerk/CORS).' : error.message;
      setStatus(message, 'error');
    } finally {
      $('#convert').disabled = false;
    }
  }

  async function consumeShare() {
    if (!('caches' in window)) return;
    try {
      const cache = await caches.open(SHARE_CACHE);
      const response = await cache.match(SHARE_KEY);
      if (!response) return;
      await cache.delete(SHARE_KEY);
      const payload = await response.json();
      if (payload.text) {
        source.value = payload.text;
        updateLength();
        setStatus(`Geteilter Inhalt übernommen${payload.source ? ` (${payload.source})` : ''}. Upload startet…`);
        await upload();
      } else {
        setStatus(payload.error || 'Der geteilte Inhalt war leer.', 'error');
      }
    } catch {
      setStatus('Geteilte Daten konnten nicht übernommen werden. Bitte teile den Code erneut.', 'error');
    }
  }

  source.addEventListener('input', updateLength);
  $('#convert').addEventListener('click', upload);
  $('#clear').addEventListener('click', () => { source.value = ''; output.value = ''; updateLength(); setStatus('Eingabe geleert.'); });
  $('#copy').addEventListener('click', async () => {
    if (!output.value) { setStatus('Es gibt noch keinen Loadstring zum Kopieren.', 'error'); return; }
    try { await navigator.clipboard.writeText(output.value); setStatus('Loadstring in die Zwischenablage kopiert.', 'ok'); }
    catch { output.focus(); output.select(); setStatus('Automatisches Kopieren nicht erlaubt. Der Text ist markiert – bitte manuell kopieren.', 'error'); }
  });
  $('#saveToken').addEventListener('click', () => {
    const value = tokenInput.value.trim();
    if (!value) { setStatus('Bitte einen API-Token eintragen.', 'error'); return; }
    localStorage.setItem(TOKEN_KEY, value);
    tokenInput.value = '';
    setStatus('API-Token wurde lokal gespeichert.', 'ok');
  });
  $('#removeToken').addEventListener('click', () => { localStorage.removeItem(TOKEN_KEY); tokenInput.value = ''; setStatus('Gespeicherter API-Token entfernt.', 'ok'); });
  $('#settingsJump').addEventListener('click', () => { $('#settings').open = true; $('#settings').scrollIntoView({ behavior: 'smooth', block: 'center' }); });

  if (getToken()) tokenInput.placeholder = 'Token ist lokal gespeichert (leer lassen, um ihn beizubehalten)';
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
    navigator.serviceWorker.register('/sw.js').catch(() => setStatus('Service Worker konnte nicht registriert werden. HTTPS-Hosting erforderlich.', 'error'));
  }
  updateLength();
  if (new URLSearchParams(location.search).has('shared')) {
    history.replaceState({}, '', location.pathname);
    window.addEventListener('load', consumeShare, { once: true });
  }
})();
