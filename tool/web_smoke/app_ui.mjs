// Full release UI smoke (the separate run.mjs checks the WASM database probe).
// Build the normal app first, with bundled web resources. This runner never
// invokes Flutter, builds assets, or contacts an external site.
//   node tool/web_smoke/app_ui.mjs build/web [build/app_ui_smoke]
// Install the already declared Playwright Chromium browser before running.
// Screenshots and a machine-readable result are retained even on failure.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)('playwright');
const root = path.resolve(process.argv[2] ?? 'build/web');
const output = path.resolve(process.argv[3] ?? 'build/app_ui_smoke');
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
function text(name) { return page.getByText(name, { exact: typeof name === 'string' }); }
async function onScreen(locator) {
  // Flutter may recycle a lazily built semantics node between count() and
  // boundingBox(). A locator-based boundingBox() then waits for that stale
  // match until the action timeout instead of letting reveal() scroll again.
  // evaluateAll() takes a non-waiting snapshot of the currently matched nodes.
  return locator.first().evaluateAll((elements, size) => {
    const box = elements[0]?.getBoundingClientRect();
    // Audit-only synchronous observation; original predicate/actions remain unchanged.
    if (size.diagnosticStage === '08-paired-timer-reload-and-wines') {
      const describe = element => {
        const rect = element.getBoundingClientRect(), ancestors = [];
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent), r = parent.getBoundingClientRect();
          ancestors.push({ tag: parent.tagName, id: parent.id, rect: r.toJSON(), inlineStyle: parent.getAttribute('style'), transform: style.transform,
            display: style.display, visibility: style.visibility, overflow: style.overflow, scrollTop: parent.scrollTop });
        }
        const ownStyle = getComputedStyle(element);
        return { id: element.id, role: element.getAttribute('role'), label: element.getAttribute('aria-label'),
          inlineStyle: element.getAttribute('style'), computed: { transform: ownStyle.transform, display: ownStyle.display, visibility: ownStyle.visibility, overflow: ownStyle.overflow },
          rect: rect.toJSON(), ancestors };
      };
      (globalThis.__stage08Diagnostic ??= []).push({ at: new Date().toISOString(), performanceNow: performance.now(),
        location: location.href, viewport: { innerWidth, innerHeight, scrollX, scrollY },
        matchedFirst: elements[0] ? describe(elements[0]) : null,
        allWhite: [...document.querySelectorAll('[aria-label="White"]')].map(describe),
        originalPredicate: !!box && box.width > 0 && box.height > 0 &&
          box.x + box.width / 2 >= 0 && box.x + box.width / 2 < size.width &&
          box.y + box.height / 2 >= 0 && box.y + box.height / 2 < size.height - 8 });
    }
    return !!box && box.width > 0 && box.height > 0 &&
      box.x + box.width / 2 >= 0 && box.x + box.width / 2 < size.width &&
      box.y + box.height / 2 >= 0 && box.y + box.height / 2 < size.height - 8;
  }, { ...viewport, diagnosticStage: stageName });
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
    await page.mouse.move(viewport.width / 2, viewport.height / 2);
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
  if (stageName === '08-paired-timer-reload-and-wines') {
    (result.stage08PredicateFailures ??= []).push({ at: new Date().toISOString(), message });
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
  await page.mouse.move(viewport.width / 2, viewport.height / 2);
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
  browser = await chromium.launch({ headless: true });
  // A new context is a fresh profile. Its same-origin storage persists across
  // reloads in this run, but cannot modify the user's existing browser profile.
  context = await browser.newContext({ viewport, locale: 'en-US', reducedMotion: 'reduce', serviceWorkers: 'block' });
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

  await stage('01-onboarding', async () => {
    const deadline = Date.now() + startupTimeout;
    await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: startupTimeout });
    await enableAccessibility(Math.max(1, deadline - Date.now()));
    await visible('Welcome to Sommelier Study Companion', Math.max(1, deadline - Date.now()));
    await tap('I am of legal drinking age where I live.');
    await tap('Continue');
    await visible('How it works');
    await tap('Continue');
    await visible('Choose your track');
    await chooseTrack('WSET Level 2');
    await tap('Start studying');
    await visible('Home', startupTimeout);
    await checkRuntimeMessages();
    assert(await page.evaluate(() => crossOriginIsolated), 'Build server did not enable COOP/COEP.');
  });

  await stage('02-five-tracks', async () => {
    for (const label of ['WSET Level 1', 'WSET Level 2', 'WSET Level 3',
      'WSET Level 4 Diploma', 'CMS Certified Sommelier']) {
      await chooseTrack(label);
      await checkRuntimeMessages();
      await screenshot(`02-track-${label.replace(/\W+/g, '-').toLowerCase()}`);
    }
    await chooseTrack('WSET Level 2');
    result.assertions.selectableTracks = 5;
  });

  await stage('03-study-search-focus-reset', async () => {
    await navigation('Study');
    const search = page.getByRole('textbox', { name: 'Search study' });
    await search.waitFor({ state: 'visible', timeout: startupTimeout });
    await page.waitForTimeout(1500);
    const count = text(/^\d+ of \d+ facts$/).first();
    await count.waitFor();
    const factCounts = async () => {
      const match = (await count.innerText()).match(/^(\d+) of (\d+) facts$/);
      assert(match, 'Study fact counts are not readable.');
      return { matching: Number(match[1]), total: Number(match[2]) };
    };
    const baseline = await factCounts();
    assert(baseline.matching > 0 && baseline.matching === baseline.total,
      'Fresh Level 2 study view did not start with all available facts.');
    await replaceText(search, 'Chardonnay');
    await until(async () => {
      const actual = await factCounts();
      return actual.matching > 0 && actual.matching < baseline.matching &&
        actual.total === baseline.total;
    }, 'Chardonnay did not reduce the Level 2 study results to matching lessons.');
    await tap('Focus on a topic All topics');
    await tap('Geography');
    await named('Focus on a topic Geography').waitFor({ state: 'visible' });
    await visible('Reset filters');
    await replaceText(search, 'zz_ui_smoke_no_matching_wine_09127');
    await visible('No facts match these filters.');
    assert((await factCounts()).matching === 0, 'Empty search retained study results.');
    await screenshot('03-empty-study');
    await tap('Reset filters');
    await named('Focus on a topic All topics').waitFor({ state: 'visible' });
    await until(async () => {
      const actual = await factCounts();
      return await search.inputValue() === '' &&
        actual.matching === baseline.matching && actual.total === baseline.total;
    }, 'Reset did not clear the query/domain and restore all available study facts.');
    result.assertions.studySearchReducedResults = true;
    result.assertions.studyEmptySearchAndReset = true;
    await checkRuntimeMessages();
  });

  await stage('04-required-progress-focused-practice', async () => {
    await openHomeAction('View WSET progress', 'WSET progress');
    // The route may open after scrolling Home to its progress link. Inspect
    // the initial progress card from the top, after the route transition.
    await page.waitForTimeout(500);
    await top();
    await visible('Build knowledge that lasts', startupTimeout);
    // Flutter Card container paragraphs live in the group's aria-label;
    // getByText sees only child controls and misses that actual content.
    // Inspect each precise level group instead of searching text leaves.
    result.assertions.requiredProgress = [];
    for (const level of ['WSET Level 1', 'WSET Level 2', 'WSET Level 3']) {
      const metadata = scope.levels.find(row => row.title === level);
      assert(metadata, `No bundled scope for ${level}.`);
      const requiredIds = new Set(metadata.requirements.flatMap(requirement =>
        (requirement.dimensions ?? []).flatMap(dimension => dimension.itemIds)));
      assert(requiredIds.size > 0, `${level} has no declared required facts.`);
      const card = await reveal(page.getByRole('group', {
        name: new RegExp(`^${escapeRegex(level)}(?:\\s|$)`),
      }));
      const label = await card.getAttribute('aria-label');
      assert(label?.includes('Required study topics'),
        `${level} does not render its required study topics.`);
      assert(label.includes(`0 of ${requiredIds.size} available facts studied`) &&
        label.includes(`0 of ${requiredIds.size} available facts mastered`),
        `${level} required progress does not match its declared facts for a fresh learner.`);
      assert(/Optional material: 0\/\d+ studied · 0 mastered/.test(label) &&
        label.includes('It does not block this level’s study milestone.'),
        `${level} does not clearly separate optional progress from its milestone.`);
      assert(!label.includes('App study milestone complete'),
        `Fresh learner incorrectly has a completed milestone while viewing ${level}.`);
      const expectedMilestone = metadata.curriculumComplete
        ? 'Required study milestone in progress' : 'App study scope incomplete';
      assert(label.includes(expectedMilestone),
        `${level} progress does not reflect its bundled curriculum coverage flag.`);
      result.assertions.requiredProgress.push({ level, requiredFacts: requiredIds.size });
      await screenshot(`04-progress-${level.replace(/\W+/g, '-').toLowerCase()}`);
    }
    await top();
    await tap(/^Study requirements · \d+\/\d+ mastered(?:\s|$)/);
    await tap(firstL1Requirement.title, { prefix: true });
    // The catalog tile starts a focused session, not an unrelated atlas browse.
    await visible('Practice');
    await named('End session').waitFor({ state: 'visible' });
    await checkRuntimeMessages();
    result.assertions.focusedRequirement = firstL1Requirement.id;
    await tap('End session');
  });

  let savedAnswer;
  let rehearsalRemaining;
  let rehearsalDeadline;
  await stage('05-rehearsal-saved-draft', async () => {
    await navigation('Home');
    await chooseTrack('WSET Level 2');
    await openHomeAction('Level rehearsal', 'WSET practice');
    await tap('Start Level 2 practice');
    await top();
    rehearsalRemaining = await secondsRemaining();
    rehearsalDeadline = Date.now() + rehearsalRemaining * 1000;
    assert(rehearsalRemaining > 3500 && rehearsalRemaining <= 3600, 'Incorrect Level 2 duration.');
    const radio = page.getByRole('radio').first();
    await reveal(radio);
    savedAnswer = await radio.getAttribute('aria-label') || await radio.innerText();
    assert(savedAnswer?.trim(), 'First rehearsal answer has no accessible label.');
    await radio.click();
    await page.getByRole('radio', { name: savedAnswer, exact: true, checked: true }).waitFor();
    assert(await text(/^Answer:/).count() === 0, 'Rehearsal reveals answers before finish.');
    await navigation('Home');
    await page.waitForTimeout(5000);
    await reload();
    await visible('Home', startupTimeout);
    await until(() => selected(named('WSET Level 2')),
      'Selected track did not survive reload.', 30_000);
    await openHomeAction('Level rehearsal', 'WSET practice');
    const after = await secondsRemaining();
    assert(after < rehearsalRemaining &&
      Math.abs(Date.now() + after * 1000 - rehearsalDeadline) <= 3000,
      'Saved rehearsal absolute deadline changed on reload.');
    await reveal(page.getByRole('radio', { name: savedAnswer, exact: true, checked: true }));
    result.assertions.rehearsalAnswerRestored = true;
    result.assertions.rehearsalTimerRestored = true;
  });

  await stage('06-rehearsal-end-and-history', async () => {
    await tap('End this attempt');
    await visible('End this practice attempt?');
    await tap('End attempt');
    await visible('Start Level 2 practice');
    await reveal(text('Saved attempts'));
    await tap(/^Level 2 ·[\s\S]*Ended draft$/);
    await top();
    await visible('Attempt ended without a score.');
    assert(await text(/^Original practice:/).count() === 0, 'Ended draft was falsely scored.');
    await tap('Choose a new practice attempt');
    await tap('Start Level 2 practice');
    await top();
    const newTimer = await secondsRemaining();
    assert(newTimer > 3500, 'A new rehearsal did not receive a new timer.');
    // Starting after browsing ended history persists the new current attempt.
    await navigation('Home');
    await reload();
    await visible('Home', startupTimeout);
    await openHomeAction('Level rehearsal', 'WSET practice');
    assert(await secondsRemaining() > 3400, 'New running rehearsal was not restored.');
  });

  await stage('07-guided-routing-and-saved-evidence', async () => {
    await openHomeAction('Guided tasting and calibration', 'Guided tasting');
    await reveal(named('Observe a physical wine', { prefix: true })
      .or(text('Observe a physical wine')));
    await tap('Start guided tasting');
    await top();
    await visible('Level 2 · Physical wine observation');
    await visible('Untimed guided practice. This is not the paired tasting examination format.');
    const white = page.getByRole('checkbox', { name: 'White', exact: true });
    await tap('White');
    await until(() => selected(white), 'Guided colour observation did not save.');
    const evidence = page.getByRole('textbox', { name: 'Your evidence' }).first();
    const draftEvidence = 'UI smoke draft: observations need a physical wine and supporting evidence.';
    await replaceText(evidence, draftEvidence);
    // Leaving flushes the serialized text writes before showing saved history.
    await tap('Leave this guided session');
    await reveal(text('Saved guided sessions'));
    await navigation('Home');
    await reload();
    await visible('Home', startupTimeout);
    await openHomeAction('Guided tasting and calibration', 'Guided tasting');
    await reveal(text('Saved guided sessions'));
    await tap('Level 2 · Physical wine', { prefix: true });
    const restored = page.getByRole('textbox', { name: 'Your evidence' }).first();
    assert(await readText(restored) === draftEvidence, 'Guided evidence was not restored exactly.');
    await top();
    await reveal(white);
    assert(await selected(white), 'Guided colour observation was not restored.');
    result.assertions.guidedEvidenceRestored = true;
    result.assertions.guidedObservationRestored = true;
  });

  await stage('08-paired-timer-reload-and-wines', async () => {
    await navigation('Home');
    await chooseTrack('WSET Level 3');
    await openHomeAction('Level 3 paired tasting', 'Paired tasting practice');
    await tap('Start two wines · 30 minutes');
    const before = await secondsRemaining();
    const pairedDeadline = Date.now() + before * 1000;
    assert(before > 1700 && before <= 1800, 'Incorrect paired tasting duration.');
    await tap('Wine 2');
    await visible(/^Wine 2 · saved original grid /);
    const white = page.getByRole('checkbox', { name: 'White', exact: true });
    await page.evaluate(() => { (globalThis.__stage08Diagnostic ??= []).push({ phase: 'before-top', at: new Date().toISOString() }); });
    await top();
    await page.evaluate(() => { (globalThis.__stage08Diagnostic ??= []).push({ phase: 'after-top', at: new Date().toISOString() }); });
    await until(() => onScreen(white), 'Wine 2 colour control did not become visible.', actionTimeout);
    const initialVisibilityDiagnostic = await page.evaluate(() => globalThis.__stage08Diagnostic ?? []);
    fs.writeFileSync(path.join(output, 'stage08-initial-visibility-diagnostic.json'), JSON.stringify(initialVisibilityDiagnostic, null, 2) + '\n');
    const matchedWhiteObservations = initialVisibilityDiagnostic.filter(row => row.matchedFirst?.label === 'White');
    result.stage08VisibilitySummary = {
      capturedAt: new Date().toISOString(), observationCount: initialVisibilityDiagnostic.length,
      matchedWhiteObservationCount: matchedWhiteObservations.length, maximumSummaryRows: 12,
      matchedWhiteRows: matchedWhiteObservations.slice(-12).map(row => ({
        at: row.at, role: row.matchedFirst.role, id: row.matchedFirst.id, rect: row.matchedFirst.rect,
        predicate: row.originalPredicate, whiteMatchCount: row.allWhite.length, viewport: row.viewport,
      })),
      boundary: 'Rows describe observations whose first matched element was labelled White; absent matches and other locators are not identified as White polls. Full observations remain in diagnostic JSON.',
    };
    // Changing wine preserves the lazy form scroll offset. Search toward
    // its colour controls so a retained lower offset cannot hide White.
    await tap('White', { direction: -1 });
    await until(() => selected(white), 'Wine 2 colour observation did not save.');
    const evidence = page.getByRole('textbox', { name: 'Your evidence' }).first();
    const wine2Evidence = 'UI smoke Wine 2 evidence: keep this distinct from Wine 1.';
    await replaceText(evidence, wine2Evidence);
    // An explicit navigation after input lets the queued write drain; the reload
    // proves persistent storage. Core regressions test writes racing deadlines.
    await page.waitForTimeout(700);
    await navigation('Home');
    await page.waitForTimeout(5000);
    await reload();
    await visible('Home', startupTimeout);
    await openHomeAction('Level 3 paired tasting', 'Paired tasting practice');
    const after = await secondsRemaining();
    assert(after < before && Math.abs(Date.now() + after * 1000 - pairedDeadline) <= 3000,
      'Paired absolute deadline changed on reload.');
    await tap('Wine 2');
    assert(await readText(evidence) === wine2Evidence, 'Wine 2 evidence was not restored exactly.');
    await top();
    await reveal(white);
    assert(await selected(white), 'Wine 2 colour observation was not restored.');
    await tap('Wine 1');
    await visible(/^Wine 1 · saved original grid /);
    await reveal(white);
    assert(!await selected(white), 'Wine 2 colour observation leaked into Wine 1.');
    assert(await readText(evidence) === '', 'Wine 2 evidence leaked into Wine 1.');
    await tap('Save and finish both wines');
    await top();
    await visible('Pair finished; answers saved.');
    await visible('0 of 2 wines have every required observation and evidence prompt. This records completeness only.');
    await reveal(text(/^Unanswered observations:/));
    await reveal(text(/^Unanswered evidence:/));
    result.assertions.pairedDeadlineRestored = true;
    result.assertions.separatePhysicalWineDrafts = true;
    result.assertions.pairedObservationRestored = true;
    result.assertions.incompletePairNotGraded = true;
  });

  await stage('09-narrow-main-navigation', async () => {
    // Navigation itself can paint before the destination's Drift/Riverpod
    // stream emits. Screenshots must show the loaded body, not a transient
    // spinner (or Home's interim progress calculation).
    const loadedTimeout = 30_000;
    for (const destination of ['Home', 'Study', 'Practice', 'Tasting', 'Cellar']) {
      await navigation(destination);
      await until(() => selected(named(destination)),
        `${destination} navigation did not select its tab.`, loadedTimeout);
      if (destination === 'Home') {
        await top();
        const card = page.getByRole('group', {
          name: /^Your WSET progress[\s\S]*Level 3/,
        });
        await card.waitFor({ state: 'visible', timeout: loadedTimeout });
        const label = await card.getAttribute('aria-label');
        assert(label && !label.includes('Calculating your progress'),
          'Home progress was still calculating.');
      } else if (destination === 'Study') {
        await page.getByRole('textbox', { name: 'Search study' })
          .waitFor({ state: 'visible', timeout: loadedTimeout });
        await text(/^\d+ of \d+ facts$/).first()
          .waitFor({ state: 'visible', timeout: loadedTimeout });
      } else if (destination === 'Practice') {
        await named('Start session').waitFor({ state: 'visible', timeout: loadedTimeout });
      } else if (destination === 'Tasting') {
        // This run saved three physical observation sessions; their dated
        // history rows prove the session stream has returned.
        await named(/Started \d{4}-\d{2}-\d{2}/).first()
          .waitFor({ state: 'visible', timeout: loadedTimeout });
      } else {
        // The fresh browser profile has no journal entries.
        await page.getByText('Your wine journal').or(page.getByLabel(/Your wine journal/))
          .first().waitFor({ state: 'visible', timeout: loadedTimeout });
      }
      if (destination !== 'Home') {
        assert(await page.getByRole('progressbar').count() === 0,
          `${destination} still shows a loading spinner.`);
      }
      await checkRuntimeMessages();
      await screenshot(`09-nav-${destination.toLowerCase()}`);
    }
    const bodyOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    assert(!bodyOverflow, 'The page overflows horizontally at 320 pixels.');
    result.assertions.narrowDestinations = 5;
  });
  await stage('10-cellar-manual-label-scan', async () => {
    await tap('Log a wine');
    await page.getByRole('heading', { name: 'Log a wine' })
      .waitFor({ state: 'visible', timeout: actionTimeout });
    await top();
    const producer = page.getByRole('textbox', { name: 'Producer', exact: true });
    const vintage = page.getByRole('textbox', { name: 'Vintage', exact: true });
    const transcript = page.getByRole('textbox', {
      name: /Recognized or manually transcribed label text/,
    });
    await replaceText(producer, 'Web Estate');
    await replaceText(transcript, 'Web Estate 2019 13.5%');
    await top();
    assert(await readText(vintage) === '',
      'A label clue filled the vintage before the learner accepted it.');
    assert(await readText(transcript) === 'Web Estate 2019 13.5%',
      'Scrolling discarded the temporary label transcription.');
    await tap('Use vintage 2019');
    await tap('Use 13.5% alcohol');
    const chooserPromise = page.waitForEvent('filechooser', { timeout: actionTimeout });
    await tap('Choose label');
    const chooser = await chooserPromise;
    await chooser.setFiles({ name: 'label.png', mimeType: 'image/png',
      buffer: fs.readFileSync(path.join(root, 'favicon.png')) });
    await reveal(page.getByRole('img', { name: 'New label' }));
    await top();
    assert(await readText(vintage) === '2019',
      'The accepted vintage did not reach the journal form.');
    await tap('Save');
    await until(() => page.url().includes('/cellar/') &&
      !page.url().includes('/cellar/new'),
    'The confirmed cellar draft did not open its saved entry.', 30_000);
    await visible('Web Estate');
    await visible('2019');
    await reveal(page.getByRole('img', { name: /Your photos Label photo/ }));
    result.assertions.manualLabelProposalSaved = true;
    result.assertions.webLabelPhotoSaved = true;
  });
  await stage('11-diploma-product-writing-persistence', async () => {
    const bankPath = path.join(root, 'assets/assets/study/diploma_written_practice.json');
    assert(fs.existsSync(bankPath), 'The build has no Diploma writing bank.');
    const bank = JSON.parse(fs.readFileSync(bankPath, 'utf8'));
    const diploma = scope.levels.find(level => level.certificationId === 'WSET_L4');
    assert(diploma && !diploma.curriculumComplete,
      'Product writing must not turn the Diploma scope into completed curriculum.');
    const loadedTimeout = 30_000;
    result.assertions.diplomaProductWriting = [];

    // At 320px, the center can hit a native textarea instead of the Flutter
    // ListView. Its 16px padding leaves this 8px gutter clear of input surfaces.
    async function gutterTop() {
      if (await page.getByRole('heading', { name: /^D[345] written practice$/ }).count()) {
        // A single large wheel can leave the lazy list mid-question. Observe
        // the actual writing header with the same bounded reverse reveal.
        await gutterReveal(text(/^App-authored (?:45-minute writing-only practice for D[45]|60-minute regional writing practice for D3)\./),
          { direction: -1 });
        return;
      }
      await page.mouse.move(8, viewport.height / 2);
      await page.mouse.wheel(0, -100_000);
      await page.waitForTimeout(200);
    }
    async function writingBodyBounds(locator) {
      return locator.evaluateAll(elements => {
        const element = elements[0];
        if (!element) return null;
        const rect = element.getBoundingClientRect();
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const overflow = getComputedStyle(parent).overflowY;
          // Flutter switches its semantics scroll body to overflow:hidden after
          // a wheel event. It still clips the control to the same body bounds.
          if (!['scroll', 'auto', 'hidden', 'clip'].includes(overflow)) continue;
          const body = parent.getBoundingClientRect();
          if (body.width <= 0 || body.height <= 0) continue;
          return {
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            bodyTop: body.top, bodyBottom: body.bottom,
            fullyInside: rect.width > 0 && rect.height > 0 &&
              rect.top >= body.top && rect.bottom <= body.bottom &&
              rect.left >= body.left && rect.right <= body.right,
          };
        }
        return null;
      });
    }
    async function writingResponseBounds(locator) {
      return locator.evaluateAll(elements => {
        const element = elements[0];
        if (!element) return null;
        const describe = node => {
          const r = node.getBoundingClientRect();
          return { x: r.x, y: r.y, width: r.width, height: r.height,
            top: r.top, bottom: r.bottom, left: r.left, right: r.right };
        };
        const rect = describe(element);
        let owner = null;
        let counter = null;
        for (let parent = element.parentElement; parent &&
          parent.tagName !== 'FLT-SEMANTICS-HOST'; parent = parent.parentElement) {
          // A neighbour's counter cannot establish this question's editable end.
          const inputs = [...parent.querySelectorAll('textarea')];
          if (inputs.some(node => node !== element)) break;
          const counters = [...parent.querySelectorAll('span')]
            .filter(node => /^\d+ characters remaining$/.test(node.textContent?.trim() ?? ''));
          if (counters.length === 1) { owner = parent; counter = counters[0]; break; }
          if (counters.length > 1) break;
        }
        let clippingBody = null;
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent);
          if (!['scroll', 'auto', 'hidden', 'clip'].includes(style.overflowY)) continue;
          const body = describe(parent);
          // The merged prompt can be taller than this body. It still clips here.
          if (body.width <= 0 || body.height <= 0) continue;
          clippingBody = { ...body, id: parent.id, tag: parent.tagName,
            overflowY: style.overflowY, overflowX: style.overflowX };
          break;
        }
        const counterRect = counter ? describe(counter) : null;
        // Saved screenshots place the editable border about 14px above the
        // owned counter. A 24px offset lands inside that lower editable area.
        const pointer = counterRect ? {
          x: rect.left + rect.width / 2, y: counterRect.top - 24,
        } : null;
        const lowerStrip = pointer ? { left: pointer.x - 4, right: pointer.x + 4,
          top: pointer.y - 8, bottom: pointer.y + 8 } : null;
        const inside = (part, body) => part && body &&
          part.left >= body.left && part.right <= body.right &&
          part.top >= body.top && part.bottom <= body.bottom;
        const viewport = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
        const counterInside = counterRect && counterRect.width > 0 && counterRect.height > 0 &&
          inside(counterRect, clippingBody) && inside(counterRect, viewport);
        const lowerInside = lowerStrip && rect.width > 0 && rect.height > 0 &&
          inside(lowerStrip, clippingBody) && inside(lowerStrip, viewport) && inside(lowerStrip, rect);
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height,
          bodyTop: clippingBody?.top, bodyBottom: clippingBody?.bottom, clippingBody,
          counter: counter ? { text: counter.textContent?.trim(), rect: counterRect } : null,
          counterOwner: owner ? { id: owner.id, tag: owner.tagName,
            responseCount: owner.querySelectorAll('textarea').length,
            responseLabel: element.getAttribute('aria-label') } : null,
          pointer, lowerStrip, counterInside: Boolean(counterInside), lowerInside: Boolean(lowerInside),
          responseReady: Boolean(counterInside && lowerInside && !element.disabled) };
      });
    }
    async function activateWritingResponse(locator) {
      const measured = await writingResponseBounds(locator);
      assert(measured?.responseReady && measured.counterOwner?.responseCount === 1,
        'Running response lacks a visible owned counter and editable lower area during ' + stageName +
        ': ' + JSON.stringify(measured));
      const point = measured.pointer;
      assert(point.x > measured.clippingBody.left && point.x < measured.clippingBody.right &&
        point.y > measured.clippingBody.top && point.y < measured.clippingBody.bottom,
        'Running response pointer would fall outside its nearest clipping body.');
      await page.mouse.click(point.x, point.y);
      const observation = { stage: stageName, at: new Date().toISOString(),
        label: await locator.getAttribute('aria-label'), point, ownership: measured.counterOwner,
        measured, afterPointer: await writingResponseBounds(locator) };
      result.writingPointerDiagnostics ??= [];
      result.writingPointerDiagnostics.push(observation);
      console.log('WRITING_POINTER_DIAGNOSTIC ' + JSON.stringify(observation));
      // Existing focus/read/trusted keyboard paths and their assertions follow.
    }
    async function captureWritingGeometry(locator) {
      return locator.evaluateAll(elements => elements.map(element => {
        const describeRect = node => {
          const rect = node.getBoundingClientRect();
          return { x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right };
        };
        const ancestors = [];
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent);
          if (!['scroll', 'auto', 'hidden', 'clip'].includes(style.overflowY) &&
            !['scroll', 'auto', 'hidden', 'clip'].includes(style.overflowX)) continue;
          ancestors.push({ tag: parent.tagName, id: parent.id, rect: describeRect(parent),
            overflowY: style.overflowY, overflowX: style.overflowX,
            scrollTop: parent.scrollTop, scrollLeft: parent.scrollLeft,
            responseLabels: [...parent.querySelectorAll('textarea')].map(node => node.getAttribute('aria-label')),
            counters: [...parent.querySelectorAll('span')].map(node => node.textContent?.trim())
              .filter(value => /^\d+ characters remaining$/.test(value ?? '')) });
        }
        const owner = element.parentElement;
        return { tag: element.tagName, label: element.getAttribute('aria-label'),
          rect: describeRect(element), focused: element.matches(':focus'), ancestors,
          immediateOwner: owner ? { tag: owner.tagName, id: owner.id,
            responseCount: owner.querySelectorAll('textarea').length,
            counters: [...owner.querySelectorAll('span')].map(node => node.textContent?.trim())
              .filter(value => /^\d+ characters remaining$/.test(value ?? '')) } : null };
      }));
    }
    async function gutterReveal(locator, { direction = 1, steps = 70, writingBody = false, writingResponse = false } = {}) {
      let lastMatchedControls = [];
      let lastMatchedAt = null;
      for (let step = 0; step <= steps; step++) {
        for (let match = 0, count = await locator.count(); match < count; match++) {
          const candidate = locator.nth(match);
          if (!writingBody && !writingResponse && await onScreen(candidate)) return candidate;
          if (writingBody || writingResponse) {
            const measured = await captureWritingGeometry(candidate);
            if (measured.length) {
              lastMatchedControls = measured;
              lastMatchedAt = new Date().toISOString();
            }
            const before = writingResponse ? await writingResponseBounds(candidate) :
              await writingBodyBounds(candidate);
            if (writingResponse ? before?.responseReady : before?.fullyInside) {
              await page.waitForTimeout(200);
              const after = writingResponse ? await writingResponseBounds(candidate) :
                await writingBodyBounds(candidate);
              const stableRect = after && ['x', 'y', 'width', 'height', 'bodyTop', 'bodyBottom']
                .every(key => Math.abs(after[key] - before[key]) <= 1);
              const stableEditableEnd = !writingResponse || (after?.responseReady &&
                after.counterOwner?.id === before.counterOwner?.id &&
                ['x', 'y'].every(key => Math.abs(after.pointer[key] - before.pointer[key]) <= 1) &&
                ['top', 'bottom', 'left', 'right'].every(key =>
                  Math.abs(after.counter.rect[key] - before.counter.rect[key]) <= 1));
              if (stableRect && stableEditableEnd &&
                (writingResponse ? after?.responseReady : after?.fullyInside)) return candidate;
            }
          }
        }
        if (step === steps) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, direction * (writingBody || writingResponse ? 160 : 540));
        await page.waitForTimeout(120);
      }
      if (writingBody || writingResponse) {
        const currentMatchedControls = await captureWritingGeometry(locator);
        const matchedControls = currentMatchedControls.length ? currentMatchedControls : lastMatchedControls;
        const observation = { stage: stageName, at: new Date().toISOString(),
          locator: String(locator), currentMatchedControls, matchedControls, lastMatchedAt,
          responseBounds: writingResponse ? await writingResponseBounds(locator) : null };
        result.writingGeometryFailures ??= [];
        result.writingGeometryFailures.push(observation);
        console.log('WRITING_GEOMETRY_FAILURE ' + JSON.stringify(observation));
      }
      throw new Error('Control could not be revealed from the list gutter during ' + stageName + ': ' + locator);
    }
    async function gutterTap(name, options = {}) {
      const target = name === 'Back' ? page.getByRole('button', { name: 'Back', exact: true }) :
        named(name, options).or(text(name));
      await (await gutterReveal(target, options)).click({ timeout: actionTimeout });
    }

    // Flutter merges a running prompt into its response field's name. Once
    // writing ends, each question becomes a named group containing its review.
    // Use those observed question identities instead of lazy-field ordinals.
    function reviewSection(question) {
      return page.getByRole('group', {
        name: new RegExp('^Prompt \\d+\\s+' + escapeRegex(question.prompt) + '\\s+Self-review:'),
      });
    }
    async function writingField(question, { review = false } = {}) {
      await gutterTop();
      if (!review) {
        const field = await gutterReveal(page.getByRole('textbox', {
          name: new RegExp('^Prompt \\d+\\s+' + escapeRegex(question.prompt) + '\\s+Your explanation$'),
        }), { writingResponse: true });
        await activateWritingResponse(field);
        return field;
      }
      return gutterReveal(reviewSection(question).getByRole('textbox', {
        name: 'What would improve this answer?', exact: true,
      }));
    }
    async function reviewControl(question, label) {
      return gutterReveal(reviewSection(question).getByRole('button', {
        name: label, exact: true,
      }), { writingBody: true });
    }
    function entryLabel(unit) { return `Open ${unit.id} app ${unit.id === "D3" ? 60 : 45}-minute writing`; }
    async function expandUnit(unit) {
      await openHomeAction('View WSET progress', 'WSET progress');
      await gutterTop();
      await gutterTap(`${unit.id} · ${unit.title}`, { prefix: true });
      await gutterReveal(named(entryLabel(unit)));
    }
    async function reviewedParticipation(unit, expected) {
      // Only the current product unit is expanded; its counter may be a text
      // leaf or part of the Diploma Card group's accessible paragraph label.
      await gutterReveal(named(entryLabel(unit)));
      const expectedText = `Written practices self-reviewed: ${expected}. ` +
        'These are participation, not examiner marks or unit passes.';
      const card = page.getByRole('group', {
        name: new RegExp(`^${escapeRegex(diploma.title)}(?:\\s|$)`),
      });
      await until(async () => {
        if (await text(expectedText).count() > 0) return true;
        return (await card.first().getAttribute('aria-label'))?.includes(expectedText);
      }, `${unit.id} did not show exactly ${expected} reviewed writing participation.`,
      loadedTimeout);
    }
    async function openWriting(unit) {
      await gutterTap(entryLabel(unit));
      await visible(`${unit.id} written practice`);
      await gutterTop();
      const qualifier = text(new RegExp(
        unit.id === "D3" ? "^App-authored 60-minute regional writing practice for D3\\." :
          `^App-authored 45-minute writing-only practice for ${unit.id}\\.`));
      await qualifier.first().waitFor({ state: 'visible', timeout: loadedTimeout });
      const label = await qualifier.first().innerText();
      assert((unit.id === 'D3'
        ? label.includes('not an official examination allocation')
        : label.includes('theory and three-wine tasting in 90 minutes') &&
          label.includes('not an official split')) &&
        label.includes('Physical wine flights are separate activities') &&
        label.includes('not official examination questions or marks'),
      `${unit.id} misrepresents its app writing timer or its evidence.`);
    }
    async function leaveWriting(unit) {
      // Navigator's Back runs the screen's PopScope and drains queued prose.
      await gutterTap('Back');
      await visible('WSET progress');
      await gutterReveal(named(entryLabel(unit)));
    }
    async function closeUnit(unit) {
      await gutterTap(`${unit.id} · ${unit.title}`, { prefix: true, direction: -1 });
      // The selected Home tab retains its nested progress route. Leave the
      // page through its visible Back control before opening another unit.
      await gutterTap('Back');
      await page.getByRole('heading', { name: 'Home', exact: true })
        .waitFor({ state: 'visible', timeout: actionTimeout });
    }

    await navigation('Home');
    await chooseTrack('WSET Level 4 Diploma');
    const verifyD3Long = process.env.SOMMELIER_VERIFY_D3_LONG === '1';
    const targetQuestionIds = ['d3_candidate_new_york_sites',
      'd3_candidate_riesling_compare', 'd3_candidate_new_world_routes'];
    const reviewedCounts = new Map();
    if (verifyD3Long) result.d3LongPackVerification = {
      requested: true, maxAttempts: 6, attemptCount: 0, status: 'pending',
      targetQuestionIds, attempts: [] };
    async function runWritingAttempt(unitId, iteration = 1) {
      const participationBefore = reviewedCounts.get(unitId) ?? 0;
      const participationAfter = participationBefore + 1;
      if (unitId === 'D3' && verifyD3Long) {
        result.d3LongPackVerification.attemptCount = iteration;
        result.d3LongPackVerification.status = 'running';
      }
      const unit = diploma.units.find(row => row.id === unitId);
      const appDuration = unitId === 'D3' ? 3600 : 2700;
      const candidates = [...bank.units, ...(bank.variants ?? [])]
        .filter(row => row.unitId === unitId);
      assert(unit && candidates.length > 0 && candidates.every(row =>
        row.durationSeconds === appDuration && row.questions.length === 3 &&
        row.questions.every(question => question.criteria.length === 4)),
      `${unitId} has an incomplete writing pack.`);

      await expandUnit(unit);
      await reviewedParticipation(unit, participationBefore);
      await openWriting(unit);
      await gutterTap(`Start ${unitId} writing`);
      await gutterTop();
      const before = await secondsRemaining();
      const deadline = Date.now() + before * 1000;
      assert(before > appDuration - 100 && before <= appDuration, `${unitId} did not start its ${appDuration / 60}-minute timer.`);
      const normalize = value => value.replace(/\s+/g, ' ').trim();
      const displayedPrompts = [];
      for (let ordinal = 1; ordinal <= 3; ordinal++) {
        await gutterTop();
        const field = await gutterReveal(page.getByRole('textbox', {
          name: new RegExp(`^Prompt ${ordinal}\\s+[\\s\\S]+\\s+Your explanation$`),
        }));
        const label = await field.getAttribute('aria-label');
        const match = label?.match(new RegExp(
          `^Prompt ${ordinal}\\s+([\\s\\S]+)\\s+Your explanation$`));
        assert(match, `${unitId} Prompt ${ordinal} lacks its question identity.`);
        displayedPrompts.push(normalize(match[1]));
      }
      const matches = candidates.filter(candidate =>
        candidate.questions.every((question, index) =>
          normalize(question.prompt) === displayedPrompts[index]));
      assert(matches.length === 1,
        `${unitId} displayed an unknown, ambiguous or mixed writing pack.`);
      const preset = matches[0];
      result.selectedWritingPacks ??= [];
      result.selectedWritingPacks.push({ unitId, iteration, attemptCount: participationAfter, title: preset.title,
        questionIds: preset.questions.map(question => question.id) });
      // Extra repetitions use distinct text so an older same-pack history cannot pass restoration.
      const attemptMarker = iteration === 1 ? '' : ' Attempt ' + iteration + '.';
      const prose = new Map(preset.questions.map(question => [question.id,
        `UI smoke ${unitId} ${question.id}: compare the supplied production, style and ` +
        'stock evidence before a conditional decision. Actual wines and missing records still need review.' + attemptMarker]));
      const improvements = new Map(preset.questions.map(question => [question.id,
        `I need a fuller sourced comparison for ${question.id}; this short saved draft ` +
        'does not yet justify the checklist criteria.' + attemptMarker]));
      assert(await named(preset.questions[0].criteria[0].text).count() === 0,
        `${unitId} exposed self-review criteria before writing ended.`);
      for (const question of preset.questions) {
        const field = await writingField(question);
        const boundsBefore = await writingBodyBounds(field);
        await replaceText(field, prose.get(question.id));
        const expectedRemaining = 20000 - prose.get(question.id).length;
        const renderedRemaining = async () => field.evaluate(element => {
          for (let parent = element.parentElement; parent &&
            parent.tagName !== 'FLT-SEMANTICS-HOST'; parent = parent.parentElement) {
            // A neighbouring question's counter cannot establish this field's delivery.
            if ([...parent.querySelectorAll('textarea')].some(node => node !== element)) return null;
            const counters = [...parent.querySelectorAll('span')]
              .map(node => node.textContent?.trim())
              .filter(value => /^\d+ characters remaining$/.test(value ?? ''));
            if (counters.length === 1) return counters[0];
          }
          return null;
        });
        await until(async () => await renderedRemaining() ===
          `${expectedRemaining} characters remaining`,
        `${unitId} ${question.id} did not update Flutter's rendered character counter.`, actionTimeout);
        const observation = { unitId, iteration, questionId: question.id, expectedRemaining,
          renderedCounter: await renderedRemaining(), boundsBefore,
          boundsAfter: await writingBodyBounds(field), at: new Date().toISOString() };
        result.writingDeliveryDiagnostics ??= [];
        result.writingDeliveryDiagnostics.push(observation);
        console.log('WRITING_DELIVERY_DIAGNOSTIC ' + JSON.stringify(observation));
        if (unitId === 'D3') await page.screenshot({
          path: path.join(output, '11-attempt-' + iteration + '-' + question.id + '-after-typing.png') });
      }
      await leaveWriting(unit);
      await reviewedParticipation(unit, participationBefore);
      await closeUnit(unit);
      await reload();
      await visible('Home', startupTimeout);
      await until(() => selected(named('WSET Level 4 Diploma')),
        `${unitId} writing did not retain the selected Diploma track.`, loadedTimeout);

      await expandUnit(unit);
      await reviewedParticipation(unit, participationBefore);
      await openWriting(unit);
      const after = await secondsRemaining();
      assert(after < before && Math.abs(Date.now() + after * 1000 - deadline) <= 3000,
        `${unitId} extended or replaced its saved absolute deadline on reload.`);
      for (const question of preset.questions) {
        const field = await writingField(question);
        assert(await readText(field) === prose.get(question.id),
          `${unitId} did not restore ${question.id}'s response exactly.`);
      }
      await gutterTap('End writing and self-review');
      // Finish adds the review controls asynchronously and changes list height.
      // Wait for that actual render before scrolling to the ended-status text.
      const renderedReviewCriterion = page.getByRole('group', {
        name: /^Prompt \d+\s+[\s\S]*Self-review:/,
      }).getByRole('checkbox').first();
      await until(async () => await renderedReviewCriterion.isVisible() &&
        await renderedReviewCriterion.isEnabled(),
      `${unitId} did not render an enabled self-review after writing ended.`, actionTimeout);
      await gutterTop();
      await gutterReveal(text('Writing ended. Compare each saved answer with the criteria and explain what to improve.'), { direction: -1 });
      await visible('Writing ended. Compare each saved answer with the criteria and explain what to improve.');
      assert(await timer().count() === 0, `${unitId} kept a running timer after writing ended.`);
      for (const question of preset.questions) {
        // An honest review with no criteria selected records participation,
        // never an automatic mark for these deliberately brief responses.
        const field = await writingField(question, { review: true });
        await replaceText(field, improvements.get(question.id));
        const save = await reviewControl(question, 'Save self-review');
        const criteria = reviewSection(question).getByRole('checkbox');
        for (let index = 0, count = await criteria.count(); index < count; index++) {
          assert(!await selected(criteria.nth(index)),
            unitId + ' brief review unexpectedly selected a criterion.');
        }
        if (unitId === 'D3' && question.id === preset.questions[0].id) {
          result.controlSnapshots ??= [];
          result.controlSnapshots.push({ stage: stageName, at: new Date().toISOString(),
            question: question.id, action: 'Save self-review', bounds: await writingBodyBounds(save) });
          await screenshot('11-writing-d3-save-ready');
        }
        await save.click({ timeout: actionTimeout });
        // Save's action is asynchronous; keep this question in view while its
        // existing button becomes Update instead of scrolling on a missing match.
        await reviewSection(question).getByRole('button', {
          name: 'Update self-review', exact: true,
        }).waitFor({ state: 'visible', timeout: actionTimeout });
      }
      await gutterTop();
      await gutterReveal(text('All three responses self-reviewed. This is participation, not a grade or pass.'), { direction: -1 });
      await visible('All three responses self-reviewed. This is participation, not a grade or pass.');
      await screenshot(`11-writing-${unitId.toLowerCase()}-reviewed`);
      await leaveWriting(unit);
      await reviewedParticipation(unit, participationAfter);
      await closeUnit(unit);
      await reload();
      await visible('Home', startupTimeout);

      await expandUnit(unit);
      await reviewedParticipation(unit, participationAfter);
      await openWriting(unit);
      await visible(`Start ${unitId} writing`);
      await gutterTap('Self-reviewed practice', { prefix: true });
      // Resuming history loads a saved snapshot, but its first checkbox may be
      // below a long prompt and absent from Flutter's lazy viewport semantics.
      // Observe the saved reviewed status, then genuinely reveal the exact
      // first question's criterion before retaining the enabled-state check.
      await visible('All three responses self-reviewed. This is participation, not a grade or pass.');
      await gutterTop();
      const resumedReviewCriterion = reviewSection(preset.questions[0])
        .getByRole('checkbox').first();
      await gutterReveal(resumedReviewCriterion, { writingBody: true });
      await until(async () => await resumedReviewCriterion.isVisible() &&
        await resumedReviewCriterion.isEnabled(),
      `${unitId} did not load its saved self-reviewed writing history.`, actionTimeout);
      await gutterTop();
      await gutterReveal(text('All three responses self-reviewed. This is participation, not a grade or pass.'), { direction: -1 });
      await visible('All three responses self-reviewed. This is participation, not a grade or pass.');
      for (const question of preset.questions) {
        const field = await writingField(question, { review: true });
        assert(await readText(field) === improvements.get(question.id),
          `${unitId} did not restore ${question.id}'s explicit self-review exactly.`);
      }
      await leaveWriting(unit);
      await reviewedParticipation(unit, participationAfter);
      await closeUnit(unit);
      await checkRuntimeMessages();
      const writtenResult = { unit: unitId, iteration, title: preset.title,
        questionIds: preset.questions.map(question => question.id),
        durationSeconds: preset.durationSeconds, responsesRestored: 3,
        selfReviewsRestored: 3, absoluteDeadlineRestored: true,
        reviewedParticipation: participationAfter, appPresetQualified: true };
      if (unitId === 'D3') result.assertions.d3RegionalWriting = writtenResult;
      else result.assertions.diplomaProductWriting.push(writtenResult);
      reviewedCounts.set(unitId, participationAfter);
      return writtenResult;
    }
    const isLongPack = attempt => attempt.questionIds.length === targetQuestionIds.length &&
      attempt.questionIds.every((id, index) => id === targetQuestionIds[index]);
    for (const unitId of ['D4', 'D5', 'D3']) {
      const firstAttempt = await runWritingAttempt(unitId, 1);
      if (unitId !== 'D3' || !verifyD3Long) continue;
      result.d3LongPackVerification.attempts.push(firstAttempt);
      let targetPassed = isLongPack(firstAttempt);
      for (let iteration = 2; !targetPassed && iteration <= 6; iteration++) {
        // Every actual random draw receives the complete existing lifecycle;
        // none is abandoned, filtered, or counted without persistence/history proof.
        const attempt = await runWritingAttempt('D3', iteration);
        result.d3LongPackVerification.attempts.push(attempt);
        targetPassed = isLongPack(attempt);
      }
      result.d3LongPackVerification.status = targetPassed ? 'passed' : 'unknown_target_not_drawn';
      if (!targetPassed) {
        throw new Error('D3 long-pack verification is unknown: the target ordered question IDs ' +
          targetQuestionIds.join(', ') + ' were not drawn in six fully tested real UI attempts. ' +
          'Observed packs: ' + result.d3LongPackVerification.attempts
            .map(attempt => attempt.questionIds.join(', ')).join(' | '));
      }
    }
  });
  await stage('12-d3-flight-draft-and-saved-history', async () => {
    const diploma = scope.levels.find(level => level.certificationId === 'WSET_L4');
    const unit = diploma.units.find(row => row.id === 'D3');
    const entry = 'Open D3 three-wine practice';
    const descriptions = [
      'UI smoke wine one: a distinct draft observation needing actual physical tasting.',
      'UI smoke wine two: a separate saved description with no physical acknowledgement.',
      'UI smoke wine three: a third partial draft, not a completed tasting record.',
    ];
    const clarities = ['Bright', 'Clear', 'Cloudy'];
    const comparison = 'UI smoke comparison: these partial drafts need three real wines and fuller evidence.';
    const review = 'UI smoke self-review: no tasting accuracy or completion is claimed by these saved drafts.';
    async function gutterTop() {
      await page.mouse.move(8, viewport.height / 2);
      await page.mouse.wheel(0, -100_000);
      await page.waitForTimeout(200);
    }
    async function gutterReveal(locator, { direction = 1, steps = 70 } = {}) {
      for (let step = 0; step <= steps; step++) {
        for (let match = 0, count = await locator.count(); match < count; match++) {
          const candidate = locator.nth(match);
          if (await onScreen(candidate)) return candidate;
        }
        if (step === steps) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, direction * 160);
        await page.waitForTimeout(120);
      }
      throw new Error('Control could not be revealed from the flight gutter during ' + stageName + ': ' + locator);
    }
    async function gutterTap(label, options = {}) {
      const target = label === 'Back' ? page.getByRole('button', { name: 'Back', exact: true }) :
        named(label, options).or(text(label));
      await (await gutterReveal(target, options)).click({ timeout: actionTimeout });
    }
    async function openUnit() {
      await openHomeAction('View WSET progress', 'WSET progress');
      await gutterTop();
      await gutterTap(unit.id + ' · ' + unit.title, { prefix: true });
      await assertNoPhysicalCredit();
      await gutterTap(entry);
      await visible('D3 Still tasting practice');
      await gutterTop();
      const qualifier = text(/^Taste three actual still wines and record what you observe\./);
      await qualifier.first().waitFor({ state: 'visible', timeout: actionTimeout });
      assert((await qualifier.first().innerText()).includes('This untimed exercise'),
        'D3 flight omitted its untimed real-wine qualification.');
    }
    async function assertNoPhysicalCredit() {
      await gutterReveal(named(entry));
      const paragraph = 'Three-wine physical practices recorded: 0. ' +
        'These are self-reviewed participation, not a tasting score or exam pass.';
      const card = page.getByRole('group', {
        name: new RegExp('^' + escapeRegex(diploma.title) + '(?:\\s|$)'),
      });
      await until(async () => await text(paragraph).count() > 0 ||
        (await card.first().getAttribute('aria-label'))?.includes(paragraph),
      'An incomplete or abandoned D3 flight granted physical participation.', 30_000);
    }
    async function leaveUnit() {
      await gutterTop();
      await gutterTap('Back');
      await visible('WSET progress');
      await assertNoPhysicalCredit();
      await gutterTap(unit.id + ' · ' + unit.title, { prefix: true, direction: -1 });
      await gutterTap('Back');
      await page.getByRole('heading', { name: 'Home', exact: true })
        .waitFor({ state: 'visible', timeout: actionTimeout });
    }
    async function wine(index) {
      await gutterTop();
      await gutterTap('Wine ' + (index + 1));
      // The observed Flutter semantics merges the wine heading and static
      // evidence captions into one group. Verify that exact wine identity and
      // its selected step before locating that wine's separately named fields.
      const panel = page.getByRole('group', {
        name: new RegExp('^Wine ' + (index + 1) + ' of 3(?:\\s|$)'),
      });
      await until(async () => await panel.count() === 1 &&
        await selected(named('Wine ' + (index + 1))),
      'D3 did not load the selected wine evidence panel.', actionTimeout);
    }
    async function descriptionField() {
      return gutterReveal(page.getByRole('textbox', { name: /^description(?:\s|$)/ }));
    }
    async function comparisonStep() {
      await gutterTop();
      await gutterTap('Compare');
      const panel = page.getByRole('group', {
        name: /^Compare and review(?:\s|$)/,
      });
      await until(async () => await panel.count() === 1 &&
        await selected(named('Compare')),
      'D3 did not load its selected comparison panel.', actionTimeout);
    }
    async function comparisonField(label) {
      return gutterReveal(page.getByRole('textbox', {
        name: new RegExp('^' + escapeRegex(label) + '(?:\\s|$)'),
      }));
    }
    async function look() {
      await gutterTop();
      const section = await gutterReveal(named('Look', { prefix: true }).or(text('Look')));
      const panel = page.getByRole('group', { name: /^Wine [123] of 3(?:\s|$)/ });
      // Observed expanded Flutter semantics includes the exact attribute label
      // in this wine group. Offscreen chips disappear from its DOM, so their
      // count cannot establish expansion state.
      const expanded = async () => /(?:^|\n)Clarity \*(?:\n|$)/
        .test((await panel.first().getAttribute('aria-label')) ?? '');
      if (!await expanded()) await section.click({ timeout: actionTimeout });
      await until(expanded, 'D3 appearance section did not expand.', actionTimeout);
      // Restart the bounded fine-scroll search above the newly expanded rows.
      await gutterTop();
      await gutterReveal(named('Bright'));
    }
    async function assertEmptyCurrentDraft() {
      await wine(0);
      assert(await readText(await descriptionField()) === '',
        'A new D3 draft inherited an older flight description.');
      await look();
      for (const clarity of clarities) {
        const chip = await gutterReveal(named(clarity));
        assert(!await selected(chip), 'A new D3 draft inherited the older clarity choice.');
      }
    }

    await openUnit();
    await gutterTap('Start three-wine still flight');
    for (let index = 0; index < 3; index++) {
      await wine(index);
      await look();
      const chip = await gutterReveal(named(clarities[index]));
      await chip.click({ timeout: actionTimeout });
      await until(() => selected(chip), 'D3 clarity choice was not selected.');
      await replaceText(await descriptionField(), descriptions[index]);
    }
    await comparisonStep();
    await replaceText(await comparisonField('Three-wine comparison'), comparison);
    await replaceText(await comparisonField('Your self-review'), review);
    await leaveUnit();
    await reload();
    await visible('Home', startupTimeout);
    await openUnit();
    for (let index = 0; index < 3; index++) {
      await wine(index);
      assert(await readText(await descriptionField()) === descriptions[index],
        'D3 draft did not restore wine ' + (index + 1) + ' description exactly.');
      await look();
      const chip = await gutterReveal(named(clarities[index]));
      assert(await selected(chip), 'D3 draft did not restore its saved clarity choice.');
    }
    await comparisonStep();
    assert(await readText(await comparisonField('Three-wine comparison')) === comparison,
      'D3 draft did not restore its exact comparison.');
    assert(await readText(await comparisonField('Your self-review')) === review,
      'D3 draft did not restore its exact self-review.');
    await gutterTap('Record physical practice');
    await gutterTop();
    await gutterReveal(text(/Complete three physical wines, their observations and evidence/), { direction: -1 });
    await visible(/Complete three physical wines, their observations and evidence/);
    await gutterTap('Abandon this flight');
    await gutterTop();
    await gutterTap('Start three-wine still flight');
    await assertEmptyCurrentDraft();
    await gutterTap('View saved flight');
    await visible('D3 Still saved flight');
    await gutterTop();
    await visible('Abandoned flight · read-only');
    assert(await page.getByRole('textbox').count() === 0,
      'Saved D3 flight history exposed editable prose controls.');
    assert(await named('Record physical practice').count() === 0 &&
      await named('Abandon this flight').count() === 0,
    'Saved D3 flight history exposed draft mutation controls.');
    for (let index = 0; index < 3; index++) {
      await gutterTop();
      const title = 'Wine ' + (index + 1) + ' of 3';
      const savedWine = await gutterReveal(named(title, { prefix: true }));
      await savedWine.click({ timeout: actionTimeout });
      // The observed saved expansion exposes its caption and static contents
      // as one button. Check exact newline values inside this wine owner.
      await until(async () => await savedWine.getAttribute('aria-description') === 'Expanded',
        'Saved D3 wine did not expand.', actionTimeout);
      const lines = (await savedWine.textContent()).split(/\r?\n/);
      assert(lines[0] === title, 'Saved D3 history selected a different wine.');
      assert(lines.includes('Clarity: ' + clarities[index]),
        'Saved D3 history did not retain wine ' + (index + 1) + ' exact clarity.');
      assert(lines.includes(descriptions[index]),
        'Saved D3 history did not retain wine ' + (index + 1) + ' exact description.');
      await gutterTop();
      await (await gutterReveal(named(title, { prefix: true })))
        .click({ timeout: actionTimeout });
    }
    await gutterReveal(text(comparison));
    await visible(comparison);
    await gutterReveal(text(review));
    await visible(review);
    await screenshot('12-d3-saved-flight-read-only');
    await gutterTop();
    await gutterTap('Back');
    await visible('D3 Still tasting practice');
    await assertEmptyCurrentDraft();
    await leaveUnit();
    await reload();
    await visible('Home', startupTimeout);
    await openUnit();
    await assertEmptyCurrentDraft();
    await leaveUnit();
    await checkRuntimeMessages();
    result.assertions.d3FlightDraftPersistence = {
      descriptionsRestored: 3, clarityChoicesRestored: 3,
      comparisonRestored: true, selfReviewRestored: true,
      incompleteSubmissionRejected: true, abandonedPacketReadOnly: true,
      newDraftPreservedAfterHistoryAndReload: true, physicalParticipation: 0,
      physicalTastingAcknowledged: false,
    };
  });
  await stage('13-cms-rehearsal-service-and-two-wine-durability', async () => {
    const bankPath = path.join(root, 'assets/assets/study/cms_certified_rehearsal.json');
    assert(fs.existsSync(bankPath), 'The build has no CMS rehearsal bank.');
    const bank = JSON.parse(fs.readFileSync(bankPath, 'utf8'));
    const servicePreset = bank.presets.find(p => p.section === 'service');
    const tastingPreset = bank.presets.find(p => p.section === 'tasting');
    const theoryPreset = bank.presets.find(p => p.section === 'theory');
    const servicePool = bank.written.filter(q => q.section === 'service');
    const comparison = bank.written.find(q => q.section === 'tasting');
    const description = bank.wineEvidencePrompts.find(p => p.id === 'description');
    assert(bank.trackId === 'CMS_CERTIFIED' && servicePreset?.durationSeconds === 900 &&
      servicePreset.writtenCount === 3 && tastingPreset?.durationSeconds === 1200 &&
      tastingPreset.wineCount === 2 && theoryPreset?.durationSeconds === 1800 &&
      description && comparison, 'The build has incomplete app-only CMS presets.');
    const qualifier = /^Original app-authored practice for CMS Europe Certified study\./;
    const reviewed = 'Self-reviewed participation saved. This is not a grade or pass.';
    const ended = 'Practice ended. Review your saved evidence and explain what to improve.';
    const descriptions = [
      'Browser durability draft, wine one: an unverified citrus observation; no physical wine was tasted.',
      'Browser durability draft, wine two: an unverified berry observation; no physical wine was tasted.',
    ];
    const comparisonText = 'Browser durability comparison: these two synthetic drafts do not establish wine identity or sensory competence.';
    const newerDescription = 'Newer CMS draft marker: this distinct unsaved-in-history packet must retain its own wine one evidence.';
    const newerComparison = 'Newer CMS comparison marker: viewing older packets must keep this current draft.';

    // These helpers are scoped to the new route. Existing stages and global
    // navigation/text helpers remain unchanged. Respect the actual clipped
    // ListView body rather than clicking under the persistent navigation bar.
    async function bodyBounds(locator) {
      return locator.evaluateAll(elements => {
        const element = elements[0];
        if (!element) return null;
        const rect = element.getBoundingClientRect();
        let top = 0, bottom = innerHeight, left = 0, right = innerWidth;
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent);
          const box = parent.getBoundingClientRect();
          if (/^(?:scroll|auto|hidden|clip)$/.test(style.overflowY)) {
            top = Math.max(top, box.top); bottom = Math.min(bottom, box.bottom);
          }
          if (/^(?:scroll|auto|hidden|clip)$/.test(style.overflowX)) {
            left = Math.max(left, box.left); right = Math.min(right, box.right);
          }
        }
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height,
          inside: rect.width > 0 && rect.height > 0 && rect.left >= left + 1 &&
            rect.right <= right - 1 && rect.top >= top + 1 && rect.bottom <= bottom - 1 };
      });
    }
    async function cmsReveal(locator, { direction = 1, steps = 70, wholeControl = true } = {}) {
      for (let step = 0; step <= steps; step++) {
        for (let index = 0, count = await locator.count(); index < count; index++) {
          const candidate = locator.nth(index);
          if (!wholeControl && await onScreen(candidate)) return candidate;
          const before = wholeControl ? await bodyBounds(candidate) : null;
          if (before?.inside) {
            await page.waitForTimeout(200);
            const after = await bodyBounds(candidate);
            if (after?.inside && ['x', 'y', 'width', 'height']
              .every(key => Math.abs(before[key] - after[key]) <= 1)) return candidate;
          }
        }
        if (step === steps) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, direction * 160);
        await page.waitForTimeout(120);
      }
      throw new Error('CMS control could not be revealed during ' + stageName + ': ' + locator);
    }
    async function cmsTop() {
      await page.mouse.move(8, viewport.height / 2);
      await page.mouse.wheel(0, -100_000);
      await page.waitForTimeout(200);
      if (page.url().includes('cms-rehearsal')) {
        await cmsReveal(text(qualifier), { direction: -1 });
      }
    }
    async function cmsTap(label, options = {}) {
      const locator = label === 'Back'
        ? page.getByRole('button', { name: 'Back', exact: true })
        : named(label, options).or(text(label));
      await (await cmsReveal(locator, options)).click({ timeout: actionTimeout });
    }
    async function openCms() {
      await navigation('Home');
      await cmsTop();
      await cmsTap('CMS Certified rehearsal', { prefix: true });
      await visible('CMS Certified rehearsal');
      await cmsTop();
      await visible(qualifier);
    }
    let firstBackCaptureTaken = false;
    async function leaveCms() {
      const capture = !firstBackCaptureTaken;
      if (capture) {
        firstBackCaptureTaken = true;
        await page.evaluate(() => {
          const describe = element => {
            if (!(element instanceof Element)) return null;
            const rect = element.getBoundingClientRect();
            return { tag: element.tagName, id: element.id, role: element.getAttribute('role'),
              label: element.getAttribute('aria-label'), text: (element.textContent ?? '').trim().slice(0, 100),
              disabled: 'disabled' in element ? element.disabled : null,
              ariaDisabled: element.getAttribute('aria-disabled'),
              ariaOwns: element.getAttribute('aria-owns'),
              rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
              inputValueLength: 'value' in element ? element.value.length : null };
          };
          const snapshot = phase => ({ phase, at: new Date().toISOString(), url: location.href,
            headings: [...document.querySelectorAll('h1,h2,h3,[role="heading"]')].map(describe),
            back: [...document.querySelectorAll('[role="button"]')]
              .filter(element => (element.getAttribute('aria-label') ?? '') === 'Back' ||
                (element.textContent ?? '').trim() === 'Back').map(describe),
            activeElement: describe(document.activeElement),
            inputs: [...document.querySelectorAll('input,textarea')].map(describe) });
          const diagnostic = { snapshot, events: [], handlers: [] };
          diagnostic.before = snapshot('before-canonical-back');
          for (const type of ['pointerdown', 'pointerup', 'click']) {
            const handler = event => {
              if (diagnostic.events.length < 100) diagnostic.events.push({
                at: new Date().toISOString(), type, x: event.clientX, y: event.clientY,
                target: describe(event.target), path: event.composedPath().slice(0, 5).map(describe),
                state: snapshot('during-' + type) });
            };
            diagnostic.handlers.push({ type, handler });
            document.addEventListener(type, handler, { capture: true, passive: true });
          }
          window.__cmsCanonicalBackDiagnostic = diagnostic;
        });
      }
      try {
        await cmsTap('Back');
        // Start the original Home assertion immediately. The passive snapshot
        // neither scrolls/focuses nor delays or retries the actual Back action.
        const afterClick = capture ? page.evaluate(() => {
          const diagnostic = window.__cmsCanonicalBackDiagnostic;
          if (diagnostic) diagnostic.afterClick = diagnostic.snapshot('after-canonical-click');
        }).catch(error => ({ captureError: String(error) })) : null;
        try {
          await visible('Home');
        } finally {
          if (afterClick) await afterClick;
        }
      } finally {
        if (capture) {
          result.cmsFirstBackActivation = await page.evaluate(() => {
            const diagnostic = window.__cmsCanonicalBackDiagnostic;
            if (!diagnostic) return { captureError: 'The passive Back observer was unavailable.' };
            const captured = { before: diagnostic.before, afterClick: diagnostic.afterClick,
              afterHomeAssertion: diagnostic.snapshot('after-home-assertion'), events: diagnostic.events,
              boundary: 'DOM event receipt does not establish Dart leave-queue entry.' };
            for (const { type, handler } of diagnostic.handlers) {
              document.removeEventListener(type, handler, true);
            }
            delete window.__cmsCanonicalBackDiagnostic;
            return captured;
          }).catch(error => ({ captureError: String(error) }));
          await fs.promises.writeFile(path.join(output, '13-cms-first-back-activation.json'),
            JSON.stringify(result.cmsFirstBackActivation, null, 2));
        }
      }
      await cmsTop();
      await until(() => selected(named('WSET Level 3')),
        'CMS rehearsal changed the selected WSET study track.', actionTimeout);
    }
    async function counts({ service = 0 } = {}) {
      await cmsTop();
      const expected = ['Theory: 0', 'Two-wine tasting: 0', 'Service decisions: ' + service];
      // Flutter exposes the three counts as one owned paragraph. Its nowrap
      // span preserves newlines in textContent, while innerText collapses them.
      const paragraph = text(/^Theory: \d+\s+Two-wine tasting: \d+\s+Service decisions: \d+$/);
      const exactLines = lines => lines.length === expected.length &&
        lines.every((line, index) => line === expected[index]);
      await until(async () => {
        const rows = await paragraph.evaluateAll(elements => elements.map(element =>
          (element.textContent ?? '').split(/\r?\n/).map(line => line.trim()).filter(Boolean)));
        return rows.length === 1 && exactLines(rows[0]);
      }, 'CMS did not show its exact saved participation counts: ' + expected.join(' | '), actionTimeout);
      const rendered = await cmsReveal(paragraph);
      const lines = await rendered.evaluate(element =>
        (element.textContent ?? '').split(/\r?\n/).map(line => line.trim()).filter(Boolean));
      assert(exactLines(lines),
        'CMS rendered different saved participation counts: ' + expected.join(' | '));
      assert(await text(/Counts are unknown/).count() === 0,
        'CMS saved-participation counts could not be read.');
    }
    function writtenOwner(question) {
      return page.getByRole('group', {
        name: new RegExp('^Written \\d+\\s+' + escapeRegex(question.prompt) + '$'),
      });
    }
    function runningWritten(question) {
      return writtenOwner(question).getByRole('textbox', { name: 'Your explanation', exact: true });
    }
    async function discoverServiceQuestions() {
      const found = new Map();
      const ordinals = new Map();
      await cmsTop();
      for (let step = 0; step <= 70; step++) {
        const labels = await page.getByRole('group', { name: /^Written \d+(?:\s|$)/ })
          .evaluateAll(elements => elements.map(element => element.getAttribute('aria-label') ?? ''));
        for (const label of labels) {
          const questions = servicePool.filter(question =>
            new RegExp('^Written (\\d+)\\s+' + escapeRegex(question.prompt) + '$').test(label));
          assert(questions.length === 1, 'CMS exposed an unknown or ambiguous saved service prompt.');
          const question = questions[0];
          const ordinal = Number(label.match(/^Written (\d+)\s/)[1]);
          assert(!ordinals.has(question.id) || ordinals.get(question.id) === ordinal,
            'CMS changed a saved prompt ordinal while revealing its snapshot.');
          assert(labels.filter(value => value === label).length === 1,
            'CMS exposed more than one owner for the same saved service prompt.');
          ordinals.set(question.id, ordinal);
          found.set(question.id, question);
        }
        if (found.size === servicePreset.writtenCount) {
          assert([...ordinals.values()].sort().join(',') === '1,2,3',
            'CMS did not expose three distinct saved service prompt ordinals.');
          return [...found.values()];
        }
        assert(found.size < servicePreset.writtenCount,
          'CMS service snapshot contains more prompts than its saved preset.');
        if (step === 70) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, 160);
        await page.waitForTimeout(120);
      }
      throw new Error('CMS did not expose all three actual saved service prompt identities.');
    }
    async function proseField(question) {
      await cmsTop();
      const field = runningWritten(question);
      const rendered = await cmsReveal(field);
      assert(await writtenOwner(question).count() === 1 && await field.count() === 1,
        'CMS did not expose one prose field owned by its exact saved prompt.');
      return rendered;
    }
    async function improvementField(question) {
      await cmsTop();
      const field = writtenOwner(question).getByRole('textbox', {
        name: 'What would improve this answer?', exact: true,
      });
      const rendered = await cmsReveal(field);
      assert(await writtenOwner(question).count() === 1 && await field.count() === 1,
        'CMS did not expose one improvement field owned by its exact saved prompt.');
      return rendered;
    }
    async function reviewControl(question, label) {
      const control = writtenOwner(question).getByRole('button', { name: label, exact: true });
      const rendered = await cmsReveal(control);
      assert(await writtenOwner(question).count() === 1 && await control.count() === 1,
        'CMS did not expose one self-review control owned by its exact saved prompt.');
      return rendered;
    }
    function wineOwner(index) {
      return page.getByRole('group', { name: 'Wine ' + (index + 1) + ' of 2', exact: true });
    }
    function wineDescriptionOwner(index) {
      return wineOwner(index).getByRole('group', { name: description.prompt, exact: true });
    }
    async function wineField(index) {
      await cmsTop();
      const prompt = wineDescriptionOwner(index);
      const field = prompt.getByRole('textbox', { name: 'Your wine evidence', exact: true });
      const rendered = await cmsReveal(field);
      assert(await wineOwner(index).count() === 1 && await prompt.count() === 1 && await field.count() === 1,
        'CMS did not expose one evidence field owned by its exact wine and supplied prompt.');
      return rendered;
    }
    function currentPacket(preset) {
      return page.getByRole('group', { name: new RegExp('^' +
        escapeRegex(preset.title) + '\\s+Saved app preset: ' +
        (preset.durationSeconds / 60) + ' minutes\\s+Saved bank ' +
        escapeRegex(bank.version) + ' · scope ' + escapeRegex(bank.scopeVersion) + '(?:\\s|$)') });
    }
    async function packetLines(preset) {
      const owner = currentPacket(preset);
      await until(() => owner.count().then(count => count === 1),
        'CMS did not expose exactly one current ' + preset.section + ' snapshot.', actionTimeout);
      const lines = (await owner.getAttribute('aria-label'))?.split(/\r?\n/)
        .map(line => line.trim()).filter(Boolean) ?? [];
      const expectedHeader = [preset.title,
        'Saved app preset: ' + (preset.durationSeconds / 60) + ' minutes',
        'Saved bank ' + bank.version + ' · scope ' + bank.scopeVersion];
      assert(expectedHeader.every((line, index) => lines[index] === line),
        'CMS rendered a different current preset, saved duration, bank or scope.');
      return { owner, lines };
    }
    async function deadlineSample(duration, phase) {
      await cmsTop();
      const presets = bank.presets.filter(preset => preset.durationSeconds === duration);
      assert(presets.length === 1, 'CMS has an ambiguous saved timer preset.');
      const preset = presets[0];
      await cmsReveal((await packetLines(preset)).owner, { wholeControl: false });
      const { lines } = await packetLines(preset);
      const timers = lines.filter(line => /^Time remaining: \d+:\d{2}$/.test(line));
      assert(timers.length === 1, 'CMS did not render exactly one saved ' + phase + ' timer.');
      const match = timers[0].match(/^Time remaining: (\d+):(\d{2})$/);
      const seconds = Number(match[1]) * 60 + Number(match[2]);
      const at = Date.now();
      assert(seconds > 0 && seconds <= duration, 'CMS has an invalid saved ' + phase + ' timer.');
      return { phase, at: new Date(at).toISOString(), seconds, inferredDeadlineMs: at + seconds * 1000 };
    }
    async function firstTheoryKnowledge() {
      await cmsTop();
      const packet = await packetLines(theoryPreset);
      const first = packet.lines.filter(line => /^Knowledge 1\. /.test(line));
      const questions = bank.mcqs.filter(question => first[0] === 'Knowledge 1. ' + question.prompt);
      assert(first.length === 1 && questions.length === 1,
        'CMS did not render one exact bundled first knowledge question.');
      const question = questions[0];
      const option = packet.owner.getByRole('radio', { name: question.options[0].text, exact: true });
      await cmsReveal(option);
      assert(await option.count() === 1 && await option.isEnabled(),
        'CMS did not render the bundled first question option as an enabled owned control.');
      const { lines } = await packetLines(theoryPreset);
      assert(await text(/^Authored answer:/).count() === 0 &&
        await text(/^Knowledge feedback:/).count() === 0 &&
        !lines.some(line => /^(?:Authored answer:|Knowledge feedback:)/.test(line)),
        'CMS revealed authored choice feedback before theory ended.');
    }
    function assertSameDeadline(before, after) {
      assert(after.seconds < before.seconds &&
        Math.abs(after.inferredDeadlineMs - before.inferredDeadlineMs) <= 3000,
        'CMS extended or replaced its saved absolute deadline on reload.');
    }
    async function chooseAnother() {
      await cmsTap('Choose another practice section');
      await cmsTop();
      await cmsReveal(named('Start tasting practice'));
      await visible('Start tasting practice');
    }
    function historyOwner(preset, status) {
      return page.getByRole('group', {
        name: new RegExp('^' + escapeRegex(preset.title) + '\\s+' + escapeRegex(status)),
      });
    }
    async function openHistory(preset, status) {
      await cmsTop();
      await cmsTapIn(historyOwner(preset, status), 'View saved practice');
      await visible('Saved CMS practice');
      await cmsTop();
      await cmsReveal(text('Read-only saved snapshot. Viewing this record does not change your current draft.'));
      assert(await named('End practice and self-review').count() === 0 &&
        await named('Save reviewed participation').count() === 0,
        'Read-only CMS history exposed completion or review mutation controls.');
    }
    async function cmsTapIn(owner, label) {
      const button = owner.getByRole('button', { name: label, exact: true });
      const rendered = await cmsReveal(button);
      assert(await owner.count() === 1 && await button.count() === 1,
        'CMS did not expose one exact saved-history row owning its View control.');
      await rendered.click({ timeout: actionTimeout });
    }
    async function exactSavedValue(owner, purpose, expected, message) {
      await cmsTop();
      const leaf = owner.locator('flt-semantics:not(:has(flt-semantics))').filter({
        hasText: new RegExp('^' + escapeRegex(purpose) + '\\n'),
      });
      const actual = await cmsReveal(leaf, { wholeControl: false });
      assert(await owner.count() === 1, 'CMS saved evidence has more than one semantic owner.');
      assert(await leaf.count() === 1, 'CMS saved evidence has more than one purpose-owned static leaf.');
      const raw = await actual.evaluate(element => element.textContent ?? '');
      assert(raw === purpose + '\n' + expected, message);
      const values = await actual.evaluate(element => {
        const nodes = [element, ...element.querySelectorAll('*')];
        return nodes.flatMap(node => [
          node.getAttribute('aria-valuetext'), node.getAttribute('aria-label'),
          node.textContent, 'value' in node ? node.value : null,
        ]).filter(value => typeof value === 'string').flatMap(value => value.split(/\r?\n/));
      });
      assert(values.includes(expected), message);
    }

    await navigation('Home');
    await chooseTrack('WSET Level 3');
    await openCms();
    await counts();
    await cmsTap('Start theory practice');
    const theoryStart = await deadlineSample(1800, 'theory-start');
    assert(theoryStart.seconds > 1700, 'CMS did not start its app 30-minute theory timer.');
    await firstTheoryKnowledge();
    await cmsTap('Discard current draft');
    await visible('Discard this practice draft?');
    await cmsTap('Discard draft');
    await cmsTop();
    await cmsReveal(named('Start service practice'));

    await cmsTap('Start service practice');
    const serviceBefore = await deadlineSample(900, 'service-before-reload');
    const serviceQuestions = await discoverServiceQuestions();
    const prose = new Map(serviceQuestions.map(question => [question.id,
      'Browser service draft ' + question.id + ': check the supplied guest and stock assumptions before a conditional choice; this short explanation needs fuller evidence.']));
    const notes = new Map(serviceQuestions.map(question => [question.id,
      'For ' + question.id + ' I need to add a source-backed reason and explicit service limitation; these unchecked criteria do not claim technique competence.']));
    for (const question of serviceQuestions) {
      await replaceText(await proseField(question), prose.get(question.id));
    }
    await leaveCms();
    await reload();
    await visible('Home', startupTimeout);
    await openCms();
    const serviceAfter = await deadlineSample(900, 'service-after-reload');
    assertSameDeadline(serviceBefore, serviceAfter);
    const restoredServiceQuestions = await discoverServiceQuestions();
    assert(restoredServiceQuestions.length === serviceQuestions.length &&
      restoredServiceQuestions.every(question => prose.has(question.id)),
      'CMS replaced the saved service prompt snapshot on reload.');
    for (const question of serviceQuestions) {
      assert(await readText(await proseField(question)) === prose.get(question.id),
        'CMS did not restore service ' + question.id + ' exact prose.');
    }
    await cmsTap('End practice and self-review');
    await cmsTop();
    await until(async () => await text(ended).count() > 0,
      'CMS service did not render the ended state.', actionTimeout);
    await cmsReveal(text(ended), { direction: -1 });
    for (const question of serviceQuestions) {
      await replaceText(await improvementField(question), notes.get(question.id));
      for (const criterion of question.criteria) {
        await cmsTop();
        const checkbox = await cmsReveal(writtenOwner(question).getByRole('checkbox', {
          name: criterion.text, exact: true,
        }));
        assert(!await selected(checkbox),
          'CMS service draft selected a criterion without supporting evidence.');
      }
      const save = await reviewControl(question, 'Save self-review');
      await save.click({ timeout: actionTimeout });
      await writtenOwner(question).getByRole('button', {
        name: 'Update self-review', exact: true,
      }).waitFor({ state: 'visible', timeout: actionTimeout });
    }
    await cmsTap('Save reviewed participation');
    await cmsTop();
    await cmsReveal(text(reviewed), { direction: -1 });
    await visible(reviewed);
    await counts({ service: 1 });
    await chooseAnother();
    await leaveCms();
    await reload();
    await visible('Home', startupTimeout);
    await openCms();
    await counts({ service: 1 });
    await openHistory(servicePreset, reviewed);
    for (const question of serviceQuestions) {
      await exactSavedValue(writtenOwner(question), 'Your explanation', prose.get(question.id),
        'CMS read-only service history lost exact prose for ' + question.id + '.');
      await exactSavedValue(writtenOwner(question), 'What would improve this answer?', notes.get(question.id),
        'CMS read-only service history lost exact improvement for ' + question.id + '.');
    }
    await screenshot('13-cms-service-saved-read-only');
    await cmsTap('Back');
    await visible('CMS Certified rehearsal');

    await cmsTap('Start tasting practice');
    const tastingBefore = await deadlineSample(1200, 'two-wine-before-reload');
    for (let index = 0; index < 2; index++) {
      await replaceText(await wineField(index), descriptions[index]);
    }
    await replaceText(await proseField(comparison), comparisonText);
    await leaveCms();
    await reload();
    await visible('Home', startupTimeout);
    await openCms();
    const tastingAfter = await deadlineSample(1200, 'two-wine-after-reload');
    assertSameDeadline(tastingBefore, tastingAfter);
    for (let index = 0; index < 2; index++) {
      assert(await readText(await wineField(index)) === descriptions[index],
        'CMS did not restore exact evidence for its owned wine ' + (index + 1) + '.');
    }
    assert(await readText(await proseField(comparison)) === comparisonText,
      'CMS did not restore the exact saved two-wine comparison.');
    await cmsTop();
    const physical = await cmsReveal(named('I am recording observations from two actual wines.'));
    assert(!await selected(physical), 'Synthetic browser drafts claimed physical tasting.');
    await cmsTap('End practice and self-review');
    await cmsTop();
    await cmsReveal(text('This packet is incomplete and cannot count as reviewed participation.'));
    await visible('This packet is incomplete and cannot count as reviewed participation.');
    assert(await named('Save reviewed participation').count() === 0,
      'Incomplete CMS wine drafts exposed reviewed participation.');
    await counts({ service: 1 });
    await chooseAnother();
    await cmsTap('Start tasting practice');
    for (let index = 0; index < 2; index++) {
      assert(await readText(await wineField(index)) === '',
        'A new CMS wine inherited an earlier packet evidence value.');
    }
    assert(await readText(await proseField(comparison)) === '',
      'A new CMS draft inherited an earlier comparison.');
    await replaceText(await wineField(0), newerDescription);
    await replaceText(await proseField(comparison), newerComparison);
    const newerBeforeHistory = await deadlineSample(1200, 'newer-draft-before-history');
    await openHistory(tastingPreset, ended);
    for (let index = 0; index < 2; index++) {
      await exactSavedValue(wineDescriptionOwner(index), 'Your wine evidence', descriptions[index],
        'Read-only CMS history lost owned wine ' + (index + 1) + ' exact evidence.');
    }
    await exactSavedValue(writtenOwner(comparison), 'Your explanation', comparisonText,
      'Read-only CMS history lost its exact comparison.');
    await screenshot('13-cms-two-wine-saved-read-only');
    await cmsTap('Back');
    await visible('CMS Certified rehearsal');
    await openHistory(theoryPreset, 'Draft ended without reviewed participation.');
    await cmsReveal(text('Draft ended without reviewed participation.'), { direction: -1 });
    await visible('Draft ended without reviewed participation.');
    await cmsTap('Back');
    await visible('CMS Certified rehearsal');
    await leaveCms();
    await reload();
    await visible('Home', startupTimeout);
    await openCms();
    const newerDraft = await deadlineSample(1200, 'newer-draft-after-history-reload');
    assertSameDeadline(newerBeforeHistory, newerDraft);
    assert(await readText(await wineField(0)) === newerDescription,
      'Viewing CMS history stole or altered the newer draft wine evidence.');
    assert(await readText(await wineField(1)) === '',
      'Viewing CMS history changed the newer draft second wine.');
    assert(await readText(await proseField(comparison)) === newerComparison,
      'CMS newer draft comparison changed after history and reload.');
    await counts({ service: 1 });
    await leaveCms();
    await checkRuntimeMessages();
    result.assertions.cmsRehearsal = {
      appPresetSeconds: { theory: 1800, tasting: 1200, service: 900 },
      servicePromptsAndProseRestored: serviceQuestions.map(question => question.id),
      serviceReviewNotesRestored: serviceQuestions.length,
      serviceReviewedParticipation: 1, tastingReviewedParticipation: 0,
      theoryReviewedParticipation: 0, physicalAcknowledged: false,
      wineDescriptionsRestored: 2, comparisonRestored: true,
      savedHistoryReadOnly: true, abandonedTheoryReadOnly: true,
      newerDraftPreservedAfterHistoryAndReload: true, selectedTrackRetained: 'WSET_L3',
      deadlineSamples: [theoryStart, serviceBefore, serviceAfter, tastingBefore, tastingAfter, newerBeforeHistory, newerDraft],
      boundary: 'Browser UI durability only; synthetic prose does not establish physical tasting or service technique.',
    };
  });
  await stage('14-d3-timed-six-wine-partial-durability', async () => {
    const loadedTimeout = 30_000;
    const durationSeconds = 5400;
    const diploma = scope.levels.find(level => level.certificationId === 'WSET_L4');
    const unit = diploma.units.find(row => row.id === 'D3');
    const entry = 'Timed six-wine D3 practice';
    const descriptions = new Map([
      [0, 'Timed browser Wine 1: distinct private draft; no actual wine was tasted or evaluated.'],
      [5, 'Timed browser Wine 6: separate saved evidence; no physical acknowledgement or tasting grade.'],
    ]);
    const countText = 'Reviewed timed D3 papers: 0 grouped · 0 mixed. ' +
      'Self-reviewed participation, not a tasting grade or unit pass.';
    async function paperTop() {
      await page.mouse.move(8, viewport.height / 2);
      await page.mouse.wheel(0, -100_000);
      await page.waitForTimeout(200);
    }
    async function paperBounds(locator) {
      return locator.first().evaluateAll(elements => {
        const element = elements[0]; if (!element) return null;
        const r = element.getBoundingClientRect();
        let body = { x: 0, y: 0, width: innerWidth, height: innerHeight };
        const clips = [];
        for (let ancestor = element.parentElement; ancestor; ancestor = ancestor.parentElement) {
          const style = getComputedStyle(ancestor), b = ancestor.getBoundingClientRect();
          if (/(hidden|clip|auto|scroll)/.test(style.overflow + ' ' + style.overflowY) &&
              b.width > 0 && b.height > 0) {
            clips.push({ x: b.x, y: b.y, width: b.width, height: b.height });
            const left = Math.max(body.x, b.x), top = Math.max(body.y, b.y);
            const right = Math.min(body.x + body.width, b.right), bottom = Math.min(body.y + body.height, b.bottom);
            body = { x: left, y: top, width: right - left, height: bottom - top };
          }
        }
        return { box: { x: r.x, y: r.y, width: r.width, height: r.height }, body, clips };
      });
    }
    async function paperReveal(locator, { direction = 1, whole = false, steps = 70 } = {}) {
      for (let step = 0; step <= steps; step++) {
        for (let match = 0, count = await locator.count(); match < count; match++) {
          const target = locator.nth(match), observed = await paperBounds(target);
          if (!observed) continue;
          const { box, body } = observed;
          const visible = box.width > 0 && box.height > 0 && body.width > 0 && body.height > 0 &&
            (whole ? box.x >= body.x && box.y >= body.y && box.x + box.width <= body.x + body.width &&
              box.y + box.height <= body.y + body.height :
              box.x + box.width / 2 >= body.x && box.x + box.width / 2 < body.x + body.width &&
              box.y + box.height / 2 >= body.y && box.y + box.height / 2 < body.y + body.height);
          if (visible) return target;
        }
        if (step === steps) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, direction * 160);
        await page.waitForTimeout(120);
      }
      throw new Error('Timed-paper control could not be revealed: ' + locator +
        ' bounds=' + JSON.stringify(await paperBounds(locator)));
    }
    async function paperTap(label, options = {}) {
      await (await paperReveal(named(label, options), { ...options, whole: true })).click({ timeout: actionTimeout });
    }
    async function noParticipation() {
      const owner = page.getByRole('group', { name: new RegExp('^' + escapeRegex(diploma.title) + '(?:\\s|$)') });
      await until(async () => await text(countText).count() > 0 ||
        (await owner.first().getAttribute('aria-label'))?.includes(countText),
      'A partial timed D3 paper granted reviewed participation.', loadedTimeout);
    }
    async function openPaper() {
      await openHomeAction('View WSET progress', 'WSET progress');
      await paperTop();
      await paperTap(unit.id + ' · ' + unit.title, { prefix: true });
      await paperReveal(named(entry));
      await noParticipation();
      await paperTap(entry);
      await page.getByRole('heading', { name: entry, exact: true })
        .waitFor({ state: 'visible', timeout: actionTimeout });
    }
    async function leavePaper() {
      await paperTap('Back');
      await visible('WSET progress');
      await noParticipation();
      await paperTap(unit.id + ' · ' + unit.title, { prefix: true, direction: -1 });
      await paperTap('Back');
      await page.getByRole('heading', { name: 'Home', exact: true })
        .waitFor({ state: 'visible', timeout: actionTimeout });
    }
    async function sampleDeadline(phase) {
      const remaining = text(/^Remaining \d+:\d{2}$/);
      await remaining.waitFor({ state: 'visible', timeout: actionTimeout });
      const value = (await remaining.innerText()).match(/^Remaining (\d+):(\d{2})$/);
      assert(value, 'Timed D3 lacks a readable running deadline.');
      const seconds = Number(value[1]) * 60 + Number(value[2]), at = Date.now();
      assert(seconds > 0 && seconds <= durationSeconds, 'Timed D3 has an invalid saved duration.');
      return { phase, at: new Date(at).toISOString(), seconds, inferredDeadlineMs: at + seconds * 1000 };
    }
    async function wine(index) {
      await paperTop();
      await paperTap('Wine ' + (index + 1));
      await visible('Wine ' + (index + 1) + ' of 6');
      const physical = named('I physically tasted this still wine', { prefix: true });
      await paperReveal(physical);
      assert(!await selected(physical), 'Synthetic timed D3 draft claimed physical tasting.');
    }
    async function description() {
      return paperReveal(page.getByRole('textbox', { name: /^description(?:\s|$)/ }), { whole: true });
    }
    async function delivery(field, expected) {
      await until(async () => field.evaluate((element, length) => {
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          if ([...parent.querySelectorAll('textarea')].some(other => other !== element)) return false;
          const counters = [...parent.querySelectorAll('span')].map(node => node.textContent?.trim())
            .filter(value => /^\d+ characters remaining$/.test(value ?? ''));
          if (counters.length === 1) return counters[0] === (4000 - length) + ' characters remaining';
        }
        return false;
      }, expected.length), 'Timed D3 did not update the owned Flutter character counter.', actionTimeout);
    }
    async function savedReadOnly(index, phase) {
      await wine(index);
      const field = await description();
      assert(!await field.isEnabled() || await field.getAttribute('aria-readonly') === 'true',
        'Ended timed D3 wine evidence remained editable.');
      const snapshot = await field.evaluate(element => ({ value: element.value,
        ariaValue: element.getAttribute('aria-valuetext'), label: element.getAttribute('aria-label'),
        text: element.textContent, readOnly: element.readOnly, disabled: element.disabled }));
      result.timedPaperReadOnlySnapshots ??= [];
      result.timedPaperReadOnlySnapshots.push({ index, ...snapshot });
      const expected = descriptions.get(index);
      // Disabled Flutter semantics can expose an empty native DOM value while
      // rendering the saved text. Any actual exposed value must remain exact.
      for (const exposed of [snapshot.value, snapshot.ariaValue, snapshot.text]
        .filter(value => typeof value === 'string' && value.length > 0)) {
        assert(exposed === expected, 'Ended timed D3 Wine ' + (index + 1) + ' exposed different saved evidence.');
      }
      if (snapshot.label?.includes('Timed browser Wine ')) {
        assert(snapshot.label.split(/\r?\n/).includes(expected),
          'Ended timed D3 response line exposed different saved evidence.');
      }
      await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
      const clipboardSentinel = 'Timed D3 saved-record sentinel ' + Date.now();
      await page.evaluate(value => navigator.clipboard.writeText(value), clipboardSentinel);
      assert(await page.evaluate(() => navigator.clipboard.readText()) === clipboardSentinel,
        'Timed D3 did not establish its fresh clipboard sentinel.');
      await paperTap('Copy saved record');
      await until(async () => await page.evaluate(() => navigator.clipboard.readText()) !== clipboardSentinel,
        'Timed D3 did not replace its sentinel through the genuine saved-record action.', actionTimeout);
      const rawRecord = await page.evaluate(() => navigator.clipboard.readText());
      const copiedRecord = rawRecord.replace(/\r\n/g, '\n');
      const wineBlocks = copiedRecord.split(/\n(?=Wine [1-6]\n)/).slice(1);
      const descriptionPrompt = 'Record the appearance, aromas, flavours and structure you observed in this still wine. Distinguish your observations from any information supplied about the bottle.';
      const copiedStartedMs = Date.parse(copiedRecord.match(/^Started: (.+)$/m)?.[1] ?? '');
      const copiedDeadlineMs = Date.parse(copiedRecord.match(/^Deadline: (.+)$/m)?.[1] ?? '');
      const sections = wineBlocks.map((block, slot) => ({
        wine: slot + 1,
        neutralIdExact: block.startsWith('Wine ' + (slot + 1) + '\n'),
        physicalFlagFalse: block.split('\n').includes('Physically tasted: false'),
        descriptionExact: block.includes(descriptionPrompt + '\n' + (descriptions.get(slot) ?? '') + '\n'),
        noForeignDescription: [...descriptions].every(([owner, prose]) => owner === slot || !block.split('\n').includes(prose)),
      }));
      assert(copiedRecord.startsWith('D3 timed six-wine practice · grouped\nPrivate practice; no independently assessed grade or pass.\n') &&
        !copiedRecord.includes(clipboardSentinel) && sections.length === 6 &&
        sections.every(row => row.neutralIdExact && row.physicalFlagFalse && row.descriptionExact && row.noForeignDescription),
        'Timed D3 saved record did not preserve six distinct neutral untasted description sections exactly.');
      assert(copiedDeadlineMs - copiedStartedMs === durationSeconds * 1000 &&
        Math.abs(copiedDeadlineMs - before.inferredDeadlineMs) <= 3000 &&
        copiedRecord.split('\n').includes('End: submitted'),
        'Timed D3 saved record changed its original90-minute deadline or submitted end.');
      const priorCopies = result.assertions.timedD3PaperCopies ??= [];
      assert(priorCopies.length === 0 || copiedDeadlineMs === priorCopies[0].copiedDeadlineMs,
        'Timed D3 reopened history exported a different deadline.');
      priorCopies.push({ phase, wine: index + 1, at: new Date().toISOString(),
        exactDescriptionSections: sections, copiedStartedMs, copiedDeadlineMs,
        rawRecord, freshSentinelReplaced: true, endedSubmitted: true,
        readonlyControl: true, newlineNormalization: 'CRLF to LF only; no prose alteration.',
        boundary: 'Durable saved-record proof, not visual equality, physical tasting or a grade.' });
    }
    await navigation('Home');
    await chooseTrack('WSET Level 4 Diploma');
    await openPaper();
    await paperTop();
    const setup = text(/^Taste six actual still wines under one 90-minute deadline\./);
    await setup.waitFor({ state: 'visible', timeout: actionTimeout });
    assert((await setup.innerText()).includes('app-authored arrangement') &&
      (await setup.innerText()).includes('do not specify official paper layouts'),
    'Timed D3 omitted its original-practice arrangement boundary.');
    await paperTap('Start two groups of three');
    const before = await sampleDeadline('first-start');
    assert(before.seconds > durationSeconds - 100, 'Timed D3 did not begin its real 90-minute duration.');
    for (let index = 0; index < 6; index++) {
      assert(await named('Wine ' + (index + 1)).count() === 1,
        'Timed D3 lacks exactly six neutral wine navigation slots.');
    }
    for (const [index, value] of descriptions) {
      await wine(index);
      const field = await description();
      assert(await readText(field) === '', 'A new timed D3 wine inherited another slot draft.');
      await replaceText(field, value);
      await delivery(field, value);
    }
    for (const [index, value] of descriptions) {
      await wine(index);
      assert(await readText(await description()) === value, 'Switching timed D3 wines lost exact distinct evidence.');
    }
    await leavePaper();
    await reload();
    await visible('Home', startupTimeout);
    await until(() => selected(named('WSET Level 4 Diploma')), 'Timed paper did not retain Diploma track.', loadedTimeout);
    await openPaper();
    const after = await sampleDeadline('after-route-and-reload');
    assert(after.seconds < before.seconds && Math.abs(after.inferredDeadlineMs - before.inferredDeadlineMs) <= 3000,
      'Timed D3 reload extended or replaced its original absolute deadline.');
    for (const [index, value] of descriptions) {
      await wine(index);
      assert(await readText(await description()) === value, 'Timed D3 reload lost Wine ' + (index + 1) + ' exact evidence.');
    }
    await paperTap('End and review');
    await visible('Paper ended · saved responses');
    assert(await text(/^Remaining \d+:\d{2}$/).count() === 0, 'Ended timed D3 retained a running timer.');
    await paperTop();
    const incomplete = text('This incomplete paper can be inspected, but cannot count as reviewed six-wine participation.');
    await paperReveal(incomplete);
    await incomplete.waitFor({ state: 'visible', timeout: actionTimeout });
    const reviewSave = await paperReveal(named('Save self-review'), { whole: true });
    assert(!await reviewSave.isEnabled(), 'Partial timed D3 enabled reviewed-participation submission.');
    assert(await named('End and review').count() === 0 && await named('Abandon paper').count() === 0,
      'Ended timed D3 retained draft completion controls.');
    for (const index of descriptions.keys()) await savedReadOnly(index, 'ended');
    await paperTap('Practice menu');
    await paperTop();
    await paperReveal(page.getByRole('group', { name: /^grouped · 0 of 6 complete(?:\s|$)/ }));
    assert(await named('View').count() === 1 && await named('Resume').count() === 0,
      'Ended timed D3 history retained Resume or lacked its one saved View control.');
    await paperTap('View');
    await visible('Paper ended · saved responses');
    for (const index of descriptions.keys()) await savedReadOnly(index, 'history');
    await screenshot('14-timed-d3-incomplete-read-only-history');
    await leavePaper();
    await checkRuntimeMessages();
    result.assertions.timedD3Paper = { durationSeconds, neutralWineSlots: 6,
      testedArrangement: 'grouped', originalArrangementBoundary: true,
      distinctEvidenceSaved: [1, 6], switchedAndReloadedExactly: true,
      deadlineSamples: [before, after], partialEndedReadOnly: true,
      partialHistoryReadOnly: true, completeWineCount: 0,
      reviewedGroupedParticipation: 0, reviewedMixedParticipation: 0,
      physicalAcknowledged: false, syntheticDraftsOnly: true,
      boundary: 'Browser durability only; no physical tasting, accuracy, qualified feedback or official pass evidence.' };
  });
// Additive PR26/PR28 checks use the same real UI and bounded gutter scrolling.
  async function addonTop() {
    await page.mouse.move(8, viewport.height / 2);
    await page.mouse.wheel(0, -100_000);
    await page.waitForTimeout(200);
  }
  async function addonReveal(locator, { direction = 1, steps = 70 } = {}) {
    for (let step = 0; step <= steps; step++) {
      for (let match = 0, count = await locator.count(); match < count; match++) {
        const candidate = locator.nth(match);
        if (await onScreen(candidate)) return candidate;
      }
      if (step === steps) break;
      await page.mouse.move(8, viewport.height / 2);
      await page.mouse.wheel(0, direction * 160);
      await page.waitForTimeout(120);
    }
    throw new Error('Additive smoke control not revealed during ' + stageName + ': ' + locator);
  }
  async function addonTap(label, options = {}) {
    const locator = label === 'Back' ? page.getByRole('button', { name: 'Back', exact: true }) :
      named(label, options).or(text(label));
    await (await addonReveal(locator, options)).click({ timeout: actionTimeout });
  }
  await stage('15-focused-map-country-region-entry', async () => {
    await navigation('Home');
    await chooseTrack('WSET Level 4 Diploma');
    await navigation('Practice');
    const end = named('End session');
    if (await end.count() > 0) await end.first().click({ timeout: actionTimeout });
    await addonTop();
    await addonTap('Practice maps');
    await visible('Practice maps');
    await visible('Choose a country, region or subregion. Each session uses your normal review schedule and asks map questions only.');
    await (await addonReveal(page.getByRole('button', { name: /^Country\s+All countries$/ }))).click({ timeout: actionTimeout });
    await addonTap('France');
    const search = await addonReveal(page.getByRole('textbox', { name: /^Search region or subregion(?:\s|$)/ }));
    await replaceText(search, 'Burgundy');
    // ListTile semantics owns its exact title, geographic path and ready count.
    const region = await addonReveal(named('Burgundy', { prefix: true }));
    const scopeLabel = (await region.getAttribute('aria-label')) ?? (await region.textContent()) ?? '';
    assert(/^Burgundy(?:\s|$)/.test(scopeLabel) && scopeLabel.includes('France'),
      'Focused map result lacks its Burgundy identity and France parent.');
    const ready = scopeLabel.match(/(\d+) map facts\s*·\s*(\d+) ready/);
    assert(ready && Number(ready[1]) > 0 && Number(ready[2]) > 0,
      'Focused Burgundy scope has no actual ready mapped facts.');
    await region.click({ timeout: actionTimeout });
    await page.getByRole('heading', { name: 'Practice', exact: true })
      .waitFor({ state: 'visible', timeout: actionTimeout });
    const formats = ['Find it on the map', 'Name it on the map', 'Find several places', 'Grapes on the map'];
    let format;
    await until(async () => {
      for (const label of formats) {
        const match = named(new RegExp('^' + escapeRegex(label) + '(?: · reverse)?$'));
        if (await match.count() > 0) { format = label; return true; }
      }
      return false;
    }, 'Focused map practice did not serve one of the four registered map formats.', 30_000);
    assert(!page.url().includes('/practice/maps'), 'Focused region never entered the practice route.');
    await checkRuntimeMessages();
    await (await reveal(named('End session'), { steps: 0 })).click({ timeout: actionTimeout });
    await navigation('Home');
    await visible('Home');
    result.assertions.focusedMapEntry = { activeTrack: 'WSET_L4', country: 'France', region: 'Burgundy',
      servedFormat: format, scopeLabel, readyFacts: Number(ready[2]), answered: false,
      boundary: 'Entry, served format and live scoped readiness only; exact item-set confinement is checked by native planner tests.' };
  });
  await stage('16-d3-named-six-wine-draft-isolation', async () => {
    const diploma = scope.levels.find(level => level.certificationId === 'WSET_L4');
    const unit = diploma.units.find(row => row.id === 'D3');
    const values = new Map([
      [1, new Map([[0, 'Session one Wine1 synthetic draft, not a tasted wine.'],
        [5, 'Session one Wine6 distinct synthetic draft, no physical credit.']])],
      [2, new Map([[0, 'Session two Wine1 separate synthetic draft, not session one.'],
        [5, 'Session two Wine6 own synthetic draft, no physical credit.']])],
    ]);
    const comparisons = new Map([[1, 'Session one six-slot comparison: synthetic draft only.'],
      [2, 'Session two six-slot comparison: independent synthetic draft only.']]);
    async function noCredit() {
      await addonReveal(named('Open D3 six-wine session 1', { prefix: true }));
      const namedParagraph = 'Six-wine named sessions recorded: 0 of 2. These are self-reviewed participation, not a tasting score or exam pass. Three-wine practices and timed papers count separately.';
      const legacyParagraph = 'Three-wine physical practices recorded: 0. These are self-reviewed participation, not a tasting score or exam pass.';
      const card = page.getByRole('group', { name: new RegExp('^' + escapeRegex(diploma.title) + '(?:\\s|$)') });
      for (const paragraph of [namedParagraph, legacyParagraph]) {
        await until(async () => await text(paragraph).count() > 0 ||
          (await card.first().getAttribute('aria-label'))?.includes(paragraph),
        'Synthetic named drafts granted physical participation.', 30_000);
      }
    }
    async function open(session) {
      await openHomeAction('View WSET progress', 'WSET progress');
      await addonTop();
      await addonTap(unit.id + ' · ' + unit.title, { prefix: true });
      await noCredit();
      await addonTap('Open D3 six-wine session ' + session, { prefix: true });
      await visible('D3 session ' + session + ' Still tasting practice');
      await addonTop();
      await visible(/^Taste six actual still wines and record what you observe\./);
      await visible(session === 1 ?
        'App-authored session 1: structure and origin. This is separate from timed six-wine papers and three-wine practice.' :
        'App-authored session 2: style and production. This is separate from timed six-wine papers and three-wine practice.');
    }
    async function leave() {
      await addonTop();
      await addonTap('Back');
      await visible('WSET progress');
      await noCredit();
      await addonTap(unit.id + ' · ' + unit.title, { prefix: true, direction: -1 });
      await addonTap('Back');
      await visible('Home');
    }
    async function wine(index) {
      await addonTop();
      await addonTap('Wine ' + (index + 1));
      const panel = page.getByRole('group', { name: new RegExp('^Wine ' + (index + 1) + ' of 6(?:\\s|$)') });
      await until(async () => await panel.count() === 1 && await selected(named('Wine ' + (index + 1))),
        'Named session did not load its exact six-wine slot.');
      const physical = await addonReveal(named('I physically tasted this still wine', { prefix: true }));
      assert(!await selected(physical), 'Named draft inherited a physical tasting acknowledgment.');
    }
    async function description() {
      return addonReveal(page.getByRole('textbox', { name: /^description(?:\s|$)/ }));
    }
    async function comparison() {
      await addonTop();
      await addonTap('Compare');
      const complete = page.getByRole('group', { name: /^Compare and review\s+Complete physical wines: 0 of 6\s+Recording a flight means you documented 6 real wines and reviewed your reasoning\. It is not a tasting score or exam result\.$/ });
      await addonReveal(complete);
      await complete.waitFor({ state: 'visible', timeout: actionTimeout });
      return addonReveal(page.getByRole('textbox', { name: /^Six-wine comparison(?:\s|$)/ }));
    }
    for (const session of [1, 2]) {
      await open(session);
      await addonReveal(text('Saved flights\nNo flights recorded yet.'));
      assert(await named('View saved flight').count() === 0,
        'Named session exposed the older legacy or other session history.');
      await addonTop();
      await addonTap('Start six-wine still flight');
      for (const [index, value] of values.get(session)) {
        await wine(index);
        assert(await readText(await description()) === '', 'Fresh named slot inherited another flight prose.');
        await replaceText(await description(), value);
      }
      await replaceText(await comparison(), comparisons.get(session));
      await leave();
    }
    await reload();
    await visible('Home', startupTimeout);
    await until(() => selected(named('WSET Level 4 Diploma')), 'Named sessions did not retain the Diploma track.', 30_000);
    for (const session of [2, 1]) {
      await open(session);
      assert(await named('Start six-wine still flight').count() === 0,
        'Named session lost its saved current pointer after reload.');
      for (let index = 0; index < 6; index++) {
        await wine(index);
        const actual = await readText(await description());
        const expected = values.get(session).get(index) ?? '';
        assert(actual === expected, 'Named session ' + session + ' Wine ' + (index + 1) + ' did not restore its own exact prose.');
        for (const [otherSession, otherValues] of values) {
          if (otherSession !== session) assert(![...otherValues.values()].includes(actual),
            'Named session displayed another session\'s prose.');
        }
      }
      assert(await readText(await comparison()) === comparisons.get(session),
        'Named session comparison was changed or crossed during reload.');
      await leave();
    }
    // The stage12 historical three-wine draft remains separate and empty.
    await openHomeAction('View WSET progress', 'WSET progress');
    await addonTop();
    await addonTap(unit.id + ' · ' + unit.title, { prefix: true });
    await noCredit();
    await addonTap('Open D3 three-wine practice');
    await visible('D3 Still tasting practice');
    await addonTop();
    await addonTap('Wine 1');
    const oldPanel = page.getByRole('group', { name: /^Wine 1 of 3(?:\s|$)/ });
    await until(() => oldPanel.count().then(count => count === 1), 'Legacy D3 draft no longer has three wine slots.');
    assert(await readText(await description()) === '', 'Named-session prose contaminated the historical legacy draft.');
    await addonTop();
    await addonTap('Back');
    await visible('WSET progress');
    await noCredit();
    await addonTap(unit.id + ' · ' + unit.title, { prefix: true, direction: -1 });
    await addonTap('Back');
    await visible('Home');
    await checkRuntimeMessages();
    result.assertions.namedD3DraftIsolation = { sessions: ['D3_1', 'D3_2'], wineSlotsEach: 6,
      distinctProseSlotsEach: [1, 6], allSixSlotsCheckedAfterReload: true, ownComparisonsRestored: true,
      namedHistoryDidNotExposeLegacy: true, legacyThreeWineDraftUnchanged: true,
      physicalParticipation: 0, physicalAcknowledged: false,
      boundary: 'Synthetic draft persistence and isolation only; no real-wine participation, tasting score or exam evidence.' };
  });
  await waitForFontManifest(currentDocumentLoaderId, 'final document');
  await waitForTransientRequests('final browser check');
  assertNoBrowserErrors();
  result.ok = true;
} catch (error) {
  result.failureCaughtAt = new Date().toISOString();
  result.failedStage = stageName;
  result.error = error.stack ?? String(error);
  if (page && !page.isClosed()) {
    result.failureCaptureTimes = { inputStartedAt: new Date().toISOString() };
    result.failureInputState = await inputState().catch(() => null);
    result.failureCaptureTimes.inputCompletedAt = new Date().toISOString();
    result.failureCaptureTimes.screenshotStartedAt = new Date().toISOString();
    await screenshot('failure').catch(() => {});
    result.failureCaptureTimes.screenshotCompletedAt = new Date().toISOString();
    result.failureCaptureTimes.htmlStartedAt = new Date().toISOString();
    await page.content().then(html => fs.promises.writeFile(
      path.join(output, 'failure.html'), html)).catch(() => {});
    result.failureCaptureTimes.htmlCompletedAt = new Date().toISOString();
    result.failureCaptureTimes.accessibilityStartedAt = new Date().toISOString();
    await page.locator('body').ariaSnapshot().then(snapshot => fs.promises.writeFile(
      path.join(output, 'failure-accessibility.txt'), snapshot)).catch(() => {});
    result.failureCaptureTimes.accessibilityCompletedAt = new Date().toISOString();
  }
} finally {
  if (page) {
    const diagnostic = await page.evaluate(() => globalThis.__stage08Diagnostic ?? []).catch(error => ({ captureError: String(error) }));
    fs.writeFileSync(path.join(output, 'stage08-visibility-diagnostic.json'), JSON.stringify(diagnostic, null, 2) + '\n');
  }
  // Close only the server and browser owned by this run. No port/process kill.
  const teardownFailures = [];
  try {
    await context?.close();
  } catch (error) {
    teardownFailures.push(`Browser context close failed: ${error?.stack ?? String(error)}`);
  }
  try {
    await browser?.close();
  } catch (error) {
    teardownFailures.push(`Browser close failed: ${error?.stack ?? String(error)}`);
  }
  if (server) {
    try {
      await new Promise((resolve, reject) => server.close(error =>
        error ? reject(error) : resolve()));
    } catch (error) {
      teardownFailures.push(`Smoke server close failed: ${error?.stack ?? String(error)}`);
    }
  }
  try {
    assertNoBrowserErrors();
  } catch (error) {
    teardownFailures.push(error?.stack ?? String(error));
  }
  if (teardownFailures.length > 0) {
    result.teardownError = teardownFailures.join('\n');
    if (result.ok) {
      result.ok = false;
      result.failedStage = stageName;
      result.error = result.teardownError;
    }
  }
  result.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(output, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
  fs.writeFileSync(path.join(output, 'font-network.json'), `${JSON.stringify({
    currentDocumentLoaderId, requests: [...fontRequests.values()],
    events: fontNetworkEvents,
  }, null, 2)}\n`);
}
console.log(`APP_UI_SMOKE_RESULT ${JSON.stringify(result)}`);
if (!result.ok) process.exitCode = 1;


