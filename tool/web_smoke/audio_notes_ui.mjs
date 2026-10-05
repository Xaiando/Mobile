// Full release UI smoke (the separate run.mjs checks the WASM database probe).
// Build the normal app first, with bundled web resources. This runner never
// invokes Flutter, builds assets, or contacts an external site.
//   node tool/web_smoke/app_ui.mjs build/web [build/audio_notes_ui]
// Install the already declared Playwright Chromium browser before running.
// Screenshots and a machine-readable result are retained even on failure.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(process.argv[2] ?? 'build/web');
const output = path.resolve(process.argv[3] ?? 'build/audio_notes_ui');
// A clean browser installs and indexes the full bundled curriculum before the
// router can reveal onboarding. The same work takes about two minutes on CI.
const startupTimeout = 300_000;
const actionTimeout = 12_000;
const viewport = { width: 320, height: 780 };
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.css': 'text/css',
  '.otf': 'font/otf', '.ttf': 'font/ttf', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
};
if (!fs.existsSync(path.join(root, 'index.html'))) {
  throw new Error(`No normal app build at ${root}; build lib/main.dart first.`);
}
fs.mkdirSync(output, { recursive: true });
const scopePath = path.join(root, 'assets/assets/progress/wset_scope.json');
if (!fs.existsSync(scopePath)) throw new Error(`Missing bundled catalog: ${scopePath}`);
const scope = JSON.parse(fs.readFileSync(scopePath, 'utf8'));
const firstL1Requirement = scope.levels.find(l => l.certificationId === 'WSET_L1')?.requirements?.[0];
if (!firstL1Requirement) throw new Error('The bundled Level 1 catalog has no requirements.');

const result = {
  ok: false, build: root, viewport, startedAt: new Date().toISOString(),
  stages: [], pageErrors: [], consoleErrors: [], failedRequests: [],
  blockedExternalRequests: [], assertions: {}, inputSnapshots: [],
};
let server;
let browser;
let context;
let page;
let origin;
let stageName = 'startup';
const inflightRequests = new Set();
let lastNetworkActivityAt = Date.now();
let mainFrameId;
let currentDocumentLoaderId;
const fontRequests = new Map();
const fontNetworkEvents = [];
let serverManifestCount = 0;
function blocksReload(request) { return request.url() !== `${origin}/drift_worker.js`; }
function recordFontEvent(kind, details = {}) {
  fontNetworkEvents.push({ at: new Date().toISOString(), stage: stageName, kind, ...details });
}
function fontRequestsFor(loaderId) {
  return [...fontRequests.values()].filter(request => request.loaderId === loaderId);
}
async function waitForFontManifest(loaderId, phase) {
  assert(loaderId, `No document loader while waiting for FontManifest before ${phase}.`);
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const requests = fontRequestsFor(loaderId);
    if (requests.some(request => request.failure ||
        (request.finished && request.status !== 200))) break;
    if (requests.length > 0 && requests.every(request => request.finished)) return;
    await page.waitForTimeout(75);
  }
  throw new Error(`FontManifest did not finish for ${phase}, loader ${loaderId}: ` +
    JSON.stringify(fontRequestsFor(loaderId)));
}
async function waitForTransientRequests(phase) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (inflightRequests.size === 0 && Date.now() - lastNetworkActivityAt >= 500) {
      break;
    }
    await page.waitForTimeout(75);
  }
  assert(inflightRequests.size === 0 && Date.now() - lastNetworkActivityAt >= 500,
    `Requests stayed active before ${phase}: ${[...inflightRequests]
      .map(request => request.url()).join(', ')}`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function escapeRegex(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function named(name, { prefix = false } = {}) {
  const expression = name instanceof RegExp ? name :
    new RegExp(`^${escapeRegex(name)}${prefix ? '(?:\\s|$)' : '$'}`);
  // Flutter chips may expose checkbox semantics; destinations may be tabs or
  // buttons. Widget ValueKeys are intentionally not assumed to be DOM IDs.
  return ['button', 'checkbox', 'radio', 'tab', 'option', 'menuitem']
    .map(role => page.getByRole(role, { name: expression }))
    .reduce((a, b) => a.or(b));
}
function text(name) {
  const options = { exact: typeof name === 'string' };
  return page.getByText(name, options).or(page.getByLabel(name, options));
}
async function onScreen(locator) {
  // Flutter may recycle a lazily built semantics node between count() and
  // boundingBox(). A locator-based boundingBox() then waits for that stale
  // match until the action timeout instead of letting reveal() scroll again.
  // evaluateAll() takes a non-waiting snapshot of the currently matched nodes.
  return locator.first().evaluateAll((elements, size) => {
    const box = elements[0]?.getBoundingClientRect();
    return !!box && box.width > 0 && box.height > 0 &&
      box.x + box.width / 2 >= 0 && box.x + box.width / 2 < size.width &&
      box.y + box.height / 2 >= 0 && box.y + box.height / 2 < size.height - 8;
  }, viewport);
}
async function reveal(locator, { direction = 1, steps = 70 } = {}) {
  // Flutter ListViews scroll on the canvas. DOM scrollIntoView alone cannot
  // reveal their lazily built children. Keep this bounded, including long exams.
  for (let step = 0; step <= steps; step++) {
    for (let match = 0, count = await locator.count(); match < count; match++) {
      const candidate = locator.nth(match);
      if (await onScreen(candidate)) return candidate;
    }
    if (step === steps) break;
    await page.mouse.move(viewport.width - 4, viewport.height / 2);
    await page.mouse.wheel(0, direction * 540);
    await page.waitForTimeout(120);
  }
  throw new Error(`Control could not be revealed during ${stageName}: ${locator}`);
}
async function tap(name, options = {}) {
  const candidate = named(name, options);
  // Text leaves support author-controlled ListTile and dropdown captions.
  const target = candidate.or(text(name));
  await (await reveal(target, options)).click({ timeout: actionTimeout });
}
async function visible(name, timeout = actionTimeout) {
  await text(name).first().waitFor({ state: 'visible', timeout });
}
async function until(condition, message, timeout = actionTimeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await condition()) return;
    await page.waitForTimeout(75);
  }
  throw new Error(message);
}
async function inputState() {
  return page.evaluate(() => {
    const describe = element => element ? {
      tag: element.tagName, id: element.id,
      label: element.getAttribute('aria-label'),
      role: element.getAttribute('data-semantics-role'),
      value: 'value' in element ? element.value :
        element.isContentEditable ? element.textContent : undefined,
      disabled: 'disabled' in element ? element.disabled : undefined,
      selectionStart: 'selectionStart' in element ? element.selectionStart : undefined,
      selectionEnd: 'selectionEnd' in element ? element.selectionEnd : undefined,
      focused: element === document.activeElement,
    } : null;
    return {
      activeElement: describe(document.activeElement),
      inputs: [...document.querySelectorAll('input, textarea, [contenteditable="true"]')]
        .map(describe),
      editingHostChildren: document.querySelector('flt-text-editing-host')?.childElementCount,
      documentHasFocus: document.hasFocus(),
    };
  });
}
async function focusText(locator) {
  // Flutter's semantics input is a focus surface. Its DOM value is populated
  // from the live controller only when the editing strategy activates.
  // A retained-page probe verified focus without a preceding pointer click.
  const target = await reveal(locator);
  await page.waitForTimeout(500);
  await target.focus();
  // Semantics focus triggers Flutter's next render update. Text-input event
  // handlers attach during that update, after the DOM focus event itself.
  await page.waitForTimeout(400);
  await until(() => target.evaluate(element => element.matches(':focus') ||
    element.getRootNode().activeElement === element),
    `Flutter text field lost focus during ${stageName}.`);
}
async function readText(locator) {
  // Unfocused semantics textareas can have an empty value while the canvas
  // renders restored text. Focus only: no keys or synthetic input are sent.
  await focusText(locator);
  result.inputSnapshots.push({ stage: stageName, phase: 'focused-read',
    state: await inputState() });
  return locator.inputValue();
}
async function replaceText(locator, value) {
  // Synthetic fill/input can change the DOM without reaching Flutter.
  // Use the activated field and trusted keyboard input instead.
  await focusText(locator);
  result.inputSnapshots.push({ stage: stageName, phase: 'focused', expected: value,
    state: await inputState() });
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 20 });
  result.inputSnapshots.push({ stage: stageName, phase: 'typed', expected: value,
    state: await inputState() });
  await until(() => locator.inputValue().then(actual => actual === value),
    `Flutter text field did not receive the exact value during ${stageName}.`);
}
async function top() {
  await page.mouse.move(viewport.width - 4, viewport.height / 2);
  await page.mouse.wheel(0, -100_000);
  await page.waitForTimeout(200);
}
async function enableAccessibility(timeout = startupTimeout) {
  await page.waitForFunction(() =>
    document.querySelector('flt-semantics-placeholder') ||
    document.querySelector('flt-semantics-host, flt-semantics'),
  null, { timeout });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    // The Flutter accessibility placeholder is deliberately transparent.
    await placeholder.first().evaluate(element => element.click());
  }
}
async function reload() {
  const deadline = Date.now() + startupTimeout;
  const outgoingLoader = currentDocumentLoaderId;
  // A quiet interval can precede Flutter's deferred font-manifest fetch. Its
  // response body must finish on this document before navigation can cancel it.
  await waitForFontManifest(outgoingLoader, 'outgoing document');
  // Finish the current document's asset requests before intentionally unloading
  // it. Otherwise Chromium can cancel a late Flutter font-manifest fetch and
  // report ERR_ABORTED even though the app itself completed every UI stage.
  await waitForTransientRequests('reload');
  recordFontEvent('reload-start', { loaderId: outgoingLoader });
  await page.reload({ waitUntil: 'domcontentloaded', timeout: startupTimeout });
  await until(() => currentDocumentLoaderId && currentDocumentLoaderId !== outgoingLoader,
    'Reload did not create a new main-document loader.', 30_000);
  recordFontEvent('reload-domcontentloaded', { loaderId: currentDocumentLoaderId });
  await enableAccessibility(Math.max(1, deadline - Date.now()));
  await waitForFontManifest(currentDocumentLoaderId, 'incoming document');
}
function assertNoBrowserErrors() {
  assert(result.pageErrors.length === 0, `Uncaught browser errors: ${result.pageErrors.join('\n')}`);
  assert(result.consoleErrors.length === 0, `Browser console errors: ${result.consoleErrors.join('\n')}`);
  assert(result.blockedExternalRequests.length === 0,
    `Build attempted external resources: ${result.blockedExternalRequests.join('\n')}`);
  assert(result.failedRequests.length === 0, `Failed requests: ${JSON.stringify(result.failedRequests)}`);
}
async function navigation(label) {
  // Exclude the plain AppBar title by using the destination's interactive role.
  await (await reveal(named(label, { prefix: true }), { steps: 0 })).click();
}
async function selected(locator) {
  const item = locator.first();
  return (await Promise.all(['aria-checked', 'aria-selected', 'aria-pressed']
    .map(attribute => item.getAttribute(attribute)))).includes('true');
}
async function chooseTrack(label) {
  await top();
  const chip = named(label);
  // Track chips precede the Home content. Under a busy browser the large
  // top() wheel can still be settling; keep searching toward the chips.
  await (await reveal(chip, { direction: -1 })).click();
  const deadline = Date.now() + actionTimeout;
  while (!await selected(chip) && Date.now() < deadline) {
    await page.waitForTimeout(100);
  }
  assert(await selected(chip), `Track was not selected: ${label}`);
}
async function screenshot(name) {
  await page.screenshot({ path: path.join(output, `${name}.png`), fullPage: false });
}
async function stage(name, action) {
  stageName = name;
  const started = Date.now();
  await action();
  await screenshot(name);
  result.stages.push({ name, ok: true, elapsedMs: Date.now() - started, url: page.url() });
  console.log(`APP_UI_STAGE ${name} passed`);
}
function timer() { return text(/^Time remaining: \d+:\d{2}$/).first(); }
async function secondsRemaining() {
  await timer().waitFor({ state: 'visible', timeout: actionTimeout });
  const match = (await timer().innerText()).match(/(\d+):(\d{2})/);
  assert(match, 'No readable saved-practice timer.');
  return Number(match[1]) * 60 + Number(match[2]);
}
async function openHomeAction(label, heading) {
  await navigation('Home');
  await top();
  // Home ListTiles merge their title and supporting caption into one button.
  await tap(label, { prefix: true });
  await visible(heading);
}
async function checkRuntimeMessages() {
  const failures = [
    /The database could not be opened:/,
    /This browser cannot store data\./,
    /Progress could not be read:/,
    /The curriculum could not be read:/,
    /The session stopped:/,
    /This version of the app cannot show/,
  ];
  for (const message of failures) {
    assert(await text(message).count() === 0, `App error or persistence warning: ${message}`);
  }
}

try {
  server = http.createServer((request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      const candidate = path.resolve(root, `.${pathname}`);
      const relative = path.relative(root, candidate);
      if (relative.startsWith('..') || path.isAbsolute(relative)) {
        response.writeHead(403); response.end(); return;
      }
      let file = candidate;
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      if (!fs.existsSync(file) && !path.extname(pathname)) file = path.join(root, 'index.html');
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
        response.writeHead(404); response.end(); return;
      }
      const headers = {
        'Content-Type': types[path.extname(file)] ?? 'application/octet-stream',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cache-Control': 'no-store',
      };
      // Flutter fetches this tiny manifest again after every reload. Send its
      // body and EOF together so Chromium does not see a successful response
      // header while the separate file stream has yet to deliver the body.
      if (path.relative(root, file).split(path.sep).join('/') === 'assets/FontManifest.json') {
        const bytes = fs.readFileSync(file);
        const serverRequestId = ++serverManifestCount;
        recordFontEvent('server-received', { serverRequestId });
        response.once('finish', () => recordFontEvent('server-finished', {
          serverRequestId,
        }));
        response.once('close', () => recordFontEvent('server-closed', {
          serverRequestId, bodyFinished: response.writableFinished,
        }));
        // This public asset must revalidate on reload. Chromium can report a
        // streamed no-store fetch as ERR_ABORTED even after receiving its body.
        response.writeHead(200, { ...headers, 'Cache-Control': 'no-cache',
          'Content-Length': bytes.length });
        response.end(bytes);
        return;
      }
      response.writeHead(200, headers);
      fs.createReadStream(file).on('error', () => response.destroy()).pipe(response);
    } catch {
      response.writeHead(400); response.end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true, args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required'] });
  // A new context is a fresh profile. Its same-origin storage persists across
  // reloads in this run, but cannot modify the user's existing browser profile.
  context = await browser.newContext({ viewport, locale: 'en-US', reducedMotion: 'reduce', serviceWorkers: 'block', acceptDownloads: true, permissions: ['microphone'] });
  // The route matcher skips our asynchronous route.continue() callback for
  // same-origin assets. Playwright still disables cache when routing is on;
  // external requests remain blocked and recorded by the unchanged gate.
  await context.route(url => {
    const target = String(url);
    return !target.startsWith(`${origin}/`) && !target.startsWith('data:') &&
      !target.startsWith('blob:');
  }, async route => {
    result.blockedExternalRequests.push(route.request().url());
    await route.abort('blockedbyclient');
  });
  page = await context.newPage();
  const network = await context.newCDPSession(page);
  await network.send('Network.enable');
  mainFrameId = (await network.send('Page.getFrameTree')).frameTree.frame.id;
  network.on('Network.requestWillBeSent', event => {
    if (event.type === 'Document' && event.frameId === mainFrameId &&
        event.request.url.startsWith(`${origin}/`)) {
      currentDocumentLoaderId = event.loaderId;
      recordFontEvent('document-start', { loaderId: event.loaderId,
        requestId: event.requestId, wallTime: event.wallTime,
        timestamp: event.timestamp });
    }
    if (event.request.url === `${origin}/assets/FontManifest.json`) {
      fontRequests.set(event.requestId, {
        requestId: event.requestId, loaderId: event.loaderId,
        startedAt: new Date().toISOString(), wallTime: event.wallTime,
        timestamp: event.timestamp,
      });
      recordFontEvent('font-start', { requestId: event.requestId,
        loaderId: event.loaderId });
    }
  });
  network.on('Network.responseReceived', event => {
    const request = fontRequests.get(event.requestId);
    if (request) {
      request.status = event.response.status;
      recordFontEvent('font-response', { requestId: event.requestId,
        loaderId: request.loaderId, status: request.status,
        timestamp: event.timestamp });
    }
  });
  network.on('Network.loadingFinished', event => {
    const request = fontRequests.get(event.requestId);
    if (request) {
      request.finished = true;
      recordFontEvent('font-finished', { requestId: event.requestId,
        loaderId: request.loaderId, timestamp: event.timestamp });
    }
  });
  network.on('Network.loadingFailed', event => {
    const request = fontRequests.get(event.requestId);
    if (request) {
      request.failure = event.errorText;
      recordFontEvent('font-failed', { requestId: event.requestId,
        loaderId: request.loaderId, errorText: event.errorText,
        canceled: event.canceled, timestamp: event.timestamp });
    }
  });
  page.setDefaultTimeout(actionTimeout);
  page.on('pageerror', error => result.pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error') result.consoleErrors.push(message.text());
  });
  page.on('request', request => {
    // Drift's dedicated worker script stays open for its lifetime in Chromium.
    // Still record any failure, but do not wait for it to finish before reload.
    if (blocksReload(request)) {
      inflightRequests.add(request);
      lastNetworkActivityAt = Date.now();
    }
  });
  page.on('requestfinished', request => {
    if (blocksReload(request)) {
      inflightRequests.delete(request);
      lastNetworkActivityAt = Date.now();
    }
  });
  page.on('requestfailed', request => {
    if (blocksReload(request)) {
      inflightRequests.delete(request);
      lastNetworkActivityAt = Date.now();
    }
    result.failedRequests.push({
      url: request.url(), failure: request.failure()?.errorText,
      stage: stageName, at: new Date().toISOString(),
    });
  });

  await stage('01-startup', async () => {
    await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: startupTimeout });
    await enableAccessibility(startupTimeout);
    await visible('Welcome to Sommelier Study Companion', startupTimeout);
    // This is the isolated automated test profile, never the learner's profile.
    await tap('I am of legal drinking age where I live.');
    await tap('Continue'); await visible('How it works'); await tap('Continue');
    await visible('Choose your track'); await chooseTrack('WSET Level 2');
    await tap('Start studying'); await visible('Home', startupTimeout);
  });

  let tastingUrl;
  let recordingName;
  const downloads = [];
  async function download(name, action) {
    const waiting = page.waitForEvent('download', { timeout: 15000 });
    await action();
    const file = await waiting;
    assert(await file.failure() === null, 'Browser download failed.');
    const saved = path.join(output, name || file.suggestedFilename());
    await file.saveAs(saved);
    downloads.push({ name: file.suggestedFilename(), saved, bytes: fs.statSync(saved).size });
    return downloads.at(-1);
  }
  await stage('02-create-tasting-audio-controls', async () => {
    await page.goto(`${origin}/#/tasting/new`, { waitUntil: 'domcontentloaded' });
    await visible('New tasting', startupTimeout);
    await tap('Structured tasting', { prefix: true });
    await tap('Start tasting');
    await visible('Structured tasting');
    tastingUrl = page.url();
    await tap(/^5 Notes and wine$/);
    await visible(/^Audio notes(?:\n|$)/);
    await replaceText(page.getByRole('textbox', { name: 'Recording title' }), 'Synthetic lecture reference 077');
  });
  await stage('03-real-browser-plugin-record-pause-save', async () => {
    await tap('Record audio');
    await visible(/^Recording · /m);
    await page.waitForTimeout(2000);
    await tap('Pause'); await visible(/^Paused · /m);
    await tap('Resume'); await visible(/^Recording · /m);
    await page.waitForTimeout(1000);
    await tap('Stop and save');
    await visible(/^Synthetic lecture reference 077(?:\n|$)/);
    assert(await text(/Audio could not be completed/).count() === 0, 'Recorder or persistence failed.');
    await named('Play recording').waitFor({ state: 'visible' });
    await tap('Play recording');
    await visible(/^Synthetic lecture reference 077(?:\n|$)/);
    await page.waitForTimeout(1000);
    if (await named('Stop playback').count()) await tap('Stop playback');
    const audio = await download(null, () => tap('Download recording'));
    assert(audio.bytes > 12 && /\.(webm|m4a|ogg|wav)$/.test(audio.name), 'Invalid recorded audio download.');
    recordingName = audio.name;
  });
  await stage('04-reload-restores-recording-and-byte-identical-download', async () => {
    await page.reload({ waitUntil: 'domcontentloaded' });
    await enableAccessibility(startupTimeout);
    await visible('Structured tasting', startupTimeout);
    await tap(/^5 Notes and wine$/);
    await visible(/^Synthetic lecture reference 077(?:\n|$)/);
    const restored = await download(`restored-${recordingName}`, () => tap('Download recording'));
    assert(fs.readFileSync(restored.saved).equals(fs.readFileSync(downloads[0].saved)), 'Reload changed saved audio bytes.');
  });
  await stage('05-download-review-report-with-optional-audio', async () => {
    await page.goto(`${origin}/#/settings`, { waitUntil: 'domcontentloaded' });
    await visible('Settings', startupTimeout);
    await tap('Download test results for review', { prefix: true });
    await visible('Download a review report?');
    await named('Include audio recordings').waitFor({ state: 'visible' });
    assert(!await selected(named('Include audio recordings')), 'Audio should default to excluded.');
    await download('review-without-audio.zip', () => tap('Download ZIP'));
    await tap('Download test results for review', { prefix: true });
    await tap('Include audio recordings');
    await until(() => selected(named('Include audio recordings')), 'Optional audio did not select.');
    await download('review-with-audio.zip', () => tap('Download ZIP'));
  });
  await stage('06-desktop-layout-and-delete-recording', async () => {
    viewport.width = 1280; viewport.height = 900; await page.setViewportSize(viewport);
    await page.goto(tastingUrl, { waitUntil: 'domcontentloaded' });
    await visible('Structured tasting', startupTimeout); await tap(/^5 Notes and wine$/);
    await visible(/^Synthetic lecture reference 077(?:\n|$)/); await tap('Delete recording');
    await visible('Delete this audio note?'); await tap('Delete');
    await visible(/^No recordings yet\.$/m); await checkRuntimeMessages();
  });
  result.assertions.audioSource = 'Chromium synthetic microphone; no real microphone captured';
  result.assertions.downloads = downloads;
  assert(result.pageErrors.length === 0 && result.consoleErrors.length === 0 &&
    result.failedRequests.length === 0 && result.blockedExternalRequests.length === 0,
    'Runtime or network errors were recorded.');
  result.ok = true;
} catch (error) {
  result.error = { stage: stageName, message: String(error), stack: error.stack };
  if (page) { await screenshot('failure').catch(() => {});
    result.visibleText = await page.locator('body').innerText().catch(() => '');
    result.semantics = await page.locator('[aria-label]').evaluateAll(nodes => nodes.map(n => ({role: n.getAttribute('role'), label: n.getAttribute('aria-label')}))).catch(() => []); }
  process.exitCode = 1;
} finally {
  result.completedAt = new Date().toISOString();
  fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify({ ok: result.ok, stages: result.stages.length,
    error: result.error, output }));
  await browser?.close();
  await new Promise(resolve => server ? server.close(resolve) : resolve());
}
