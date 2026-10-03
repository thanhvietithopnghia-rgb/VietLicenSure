import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const edge = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const base = process.argv[2] || 'http://127.0.0.1:8765';
const pages = ['index.html', 'en.html', 'giao-dien.html', 'gallery-en.html', 'bao-mat-rieng-tu.html', 'security-privacy-en.html', 'chinh-sach-phan-mem.html', 'software-policy-en.html', 'tai-lieu.html', 'documentation-en.html'];
const profile = await mkdtemp(join(tmpdir(), 'vietlicensure-pages-'));
const browser = spawn(edge, ['--headless=new', '--disable-gpu', '--disable-breakpad', '--disable-crash-reporter', '--noerrdialogs', '--no-first-run', '--remote-debugging-port=9223', `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let websocket;
let call;
try {
  let target;
  for (let i = 0; i < 50; i++) {
    try {
      const targets = await (await fetch('http://127.0.0.1:9223/json')).json();
      target = targets.find(item => item.type === 'page' && !item.url.startsWith('chrome-extension://'));
      if (target) break;
    } catch {}
    await delay(100);
  }
  if (!target) throw new Error('Edge CDP did not start');
  websocket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { websocket.onopen = resolve; websocket.onerror = reject; });
  let id = 0;
  const pending = new Map();
  websocket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject } = pending.get(message.id); pending.delete(message.id);
    message.error ? reject(new Error(message.error.message)) : resolve(message.result);
  };
  call = (method, params = {}) => new Promise((resolve, reject) => {
    const callId = ++id; pending.set(callId, { resolve, reject });
    websocket.send(JSON.stringify({ id: callId, method, params }));
  });
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
  const failures = [];
  for (const page of pages) {
    const navigation = await call('Page.navigate', { url: `${base}/${page}` });
    if (navigation.errorText) console.error(`${page}: navigation error: ${navigation.errorText}`);
    let value;
    for (let attempt = 0; attempt < 20; attempt++) {
      await delay(100);
      const result = await call('Runtime.evaluate', { returnByValue: true, expression: `(() => {
      const width = document.documentElement.clientWidth;
      const offenders = [...document.querySelectorAll('body *')].filter(el => {
        const s = getComputedStyle(el); if (s.display === 'none' || s.position === 'fixed' || el.matches('.skip') || el.closest('.table-wrap')) return false;
        const r = el.getBoundingClientRect(); return r.width > 0 && (r.right > width + 1 || r.left < -1);
      }).slice(0, 8).map(el => el.tagName.toLowerCase() + (el.className ? '.' + String(el.className).trim().replace(/\\s+/g,'.') : ''));
      return { width, scrollWidth: document.documentElement.scrollWidth, offenders, h1: document.querySelectorAll('h1').length, title: document.title };
      })()` });
      value = result?.result?.value;
      if (value && value.h1 === 1 && value.title.includes('VietLicenSure')) break;
    }
    if (!value) {
      console.error(`${page}: no document metrics were returned by Edge CDP`);
      failures.push(page);
      continue;
    }
    console.log(`${page}: viewport=${value.width}, scroll=${value.scrollWidth}, overflow=${value.offenders.join(',') || 'none'}, h1=${value.h1}, title=${JSON.stringify(value.title)}`);
    if (value.scrollWidth > value.width + 1 || value.offenders.length || value.h1 !== 1 || !value.title.includes('VietLicenSure')) failures.push(page);
  }
  if (failures.length) { console.error(`Responsive verification FAIL: ${failures.join(', ')}`); process.exitCode = 1; }
  else console.log(`Responsive verification PASS: ${pages.length} pages at 390px.`);
} finally {
  try { await call?.('Browser.close'); } catch {}
  try { websocket?.close(); } catch {}
  const exited = new Promise(resolve => browser.once('exit', resolve));
  if (browser.exitCode === null) browser.kill();
  await Promise.race([exited, delay(1500)]);
  for (let attempt = 0; attempt < 8; attempt++) {
    try { await rm(profile, { recursive: true, force: true }); break; }
    catch (error) { if (attempt === 7) console.warn(`Temporary Edge profile cleanup deferred: ${error.code}`); else await delay(250); }
  }
}
