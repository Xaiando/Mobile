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
    await top();
    await until(() => onScreen(white), 'Wine 2 colour control did not become visible.', actionTimeout);
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
          if (body.width <= 0 || body.height <= rect.height) continue;
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
    async function gutterReveal(locator, { direction = 1, steps = 70, writingBody = false } = {}) {
      for (let step = 0; step <= steps; step++) {
        for (let match = 0, count = await locator.count(); match < count; match++) {
          const candidate = locator.nth(match);
          if (!writingBody && await onScreen(candidate)) return candidate;
          if (writingBody) {
            const before = await writingBodyBounds(candidate);
            if (before?.fullyInside) {
              await page.waitForTimeout(200);
              const after = await writingBodyBounds(candidate);
              if (after?.fullyInside && ['x', 'y', 'width', 'height', 'bodyTop', 'bodyBottom']
                .every(key => Math.abs(after[key] - before[key]) <= 1)) return candidate;
            }
          }
        }
        if (step === steps) break;
        await page.mouse.move(8, viewport.height / 2);
        await page.mouse.wheel(0, direction * (writingBody ? 160 : 540));
        await page.waitForTimeout(120);
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
        return gutterReveal(page.getByRole('textbox', {
          name: new RegExp('^Prompt \\d+\\s+' + escapeRegex(question.prompt) + '\\s+Your explanation$'),
        }));
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
    for (const unitId of ['D4', 'D5', 'D3']) {
      const unit = diploma.units.find(row => row.id === unitId);
      const preset = bank.units.find(row => row.unitId === unitId);
      const appDuration = unitId === 'D3' ? 3600 : 2700;
      assert(unit && preset?.durationSeconds === appDuration && preset.questions.length === 3 &&
        preset.questions.every(question => question.criteria.length === 4),
      `${unitId} has no complete ${appDuration / 60}-minute app writing preset.`);
      const prose = new Map(preset.questions.map(question => [question.id,
        `UI smoke ${unitId} ${question.id}: compare the supplied production, style and ` +
        'stock evidence before a conditional decision. Actual wines and missing records still need review.']));
      const improvements = new Map(preset.questions.map(question => [question.id,
        `I need a fuller sourced comparison for ${question.id}; this short saved draft ` +
        'does not yet justify the checklist criteria.']));

      await expandUnit(unit);
      await reviewedParticipation(unit, 0);
      await openWriting(unit);
      await gutterTap(`Start ${unitId} writing`);
      await gutterTop();
      const before = await secondsRemaining();
      const deadline = Date.now() + before * 1000;
      assert(before > appDuration - 100 && before <= appDuration, `${unitId} did not start its ${appDuration / 60}-minute timer.`);
      assert(await named(preset.questions[0].criteria[0].text).count() === 0,
        `${unitId} exposed self-review criteria before writing ended.`);
      for (const question of preset.questions) {
        const field = await writingField(question);
        await replaceText(field, prose.get(question.id));
      }
      await leaveWriting(unit);
      await reviewedParticipation(unit, 0);
      await closeUnit(unit);
      await reload();
      await visible('Home', startupTimeout);
      await until(() => selected(named('WSET Level 4 Diploma')),
        `${unitId} writing did not retain the selected Diploma track.`, loadedTimeout);

      await expandUnit(unit);
      await reviewedParticipation(unit, 0);
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
      await reviewedParticipation(unit, 1);
      await closeUnit(unit);
      await reload();
      await visible('Home', startupTimeout);

      await expandUnit(unit);
      await reviewedParticipation(unit, 1);
      await openWriting(unit);
      await visible(`Start ${unitId} writing`);
      await gutterTap('Self-reviewed practice', { prefix: true });
      // Resuming history also loads its controls asynchronously before the list
      // settles. Observe the saved review before scrolling to its status text.
      const resumedReviewCriterion = page.getByRole('group', {
        name: /^Prompt \d+\s+[\s\S]*Self-review:/,
      }).getByRole('checkbox').first();
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
      await reviewedParticipation(unit, 1);
      await closeUnit(unit);
      await checkRuntimeMessages();
      const writtenResult = { unit: unitId,
        durationSeconds: preset.durationSeconds, responsesRestored: 3,
        selfReviewsRestored: 3, absoluteDeadlineRestored: true,
        reviewedParticipation: 1, appPresetQualified: true };
      if (unitId === 'D3') result.assertions.d3RegionalWriting = writtenResult;
      else result.assertions.diplomaProductWriting.push(writtenResult);
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
  await waitForFontManifest(currentDocumentLoaderId, 'final document');
  await waitForTransientRequests('final browser check');
  assertNoBrowserErrors();
  result.ok = true;
} catch (error) {
  result.failedStage = stageName;
  result.error = error.stack ?? String(error);
  if (page && !page.isClosed()) {
    result.failureInputState = await inputState().catch(() => null);
    await screenshot('failure').catch(() => {});
    await page.content().then(html => fs.promises.writeFile(
      path.join(output, 'failure.html'), html)).catch(() => {});
    await page.locator('body').ariaSnapshot().then(snapshot => fs.promises.writeFile(
      path.join(output, 'failure-accessibility.txt'), snapshot)).catch(() => {});
  }
} finally {
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
