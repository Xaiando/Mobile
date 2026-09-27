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
const startupTimeout = 120_000;
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
  blockedExternalRequests: [], assertions: {},
};
let server;
let browser;
let context;
let page;
let origin;
let stageName = 'startup';

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
  if (!await locator.count()) return false;
  const box = await locator.first().boundingBox();
  return !!box && box.width > 0 && box.height > 0 &&
    box.x + box.width / 2 >= 0 && box.x + box.width / 2 < viewport.width &&
    box.y + box.height / 2 >= 0 && box.y + box.height / 2 < viewport.height - 8;
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
  await page.reload({ waitUntil: 'domcontentloaded', timeout: startupTimeout });
  await enableAccessibility(Math.max(1, deadline - Date.now()));
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
  await (await reveal(chip)).click();
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
  await tap(label);
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
      response.writeHead(200, {
        'Content-Type': types[path.extname(file)] ?? 'application/octet-stream',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cache-Control': 'no-store',
      });
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
  await context.route('**/*', async route => {
    const url = route.request().url();
    if (url.startsWith(`${origin}/`) || url.startsWith('data:') || url.startsWith('blob:')) {
      await route.continue();
    } else {
      result.blockedExternalRequests.push(url);
      await route.abort('blockedbyclient');
    }
  });
  page = await context.newPage();
  page.setDefaultTimeout(actionTimeout);
  page.on('pageerror', error => result.pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error') result.consoleErrors.push(message.text());
  });
  page.on('requestfailed', request => result.failedRequests.push({
    url: request.url(), failure: request.failure()?.errorText,
  }));

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
    await search.fill('Chardonnay');
    const count = text(/^\d+ of \d+ facts$/).first();
    await count.waitFor();
    await page.waitForTimeout(250);
    assert(!/^0 of/.test(await count.innerText()), 'Chardonnay search has no Level 2 lessons.');
    await tap('All topics');
    await tap('Geography');
    await visible('Reset filters');
    await search.fill('zz_ui_smoke_no_matching_wine_09127');
    await visible('No facts match these filters.');
    await screenshot('03-empty-study');
    await tap('Reset filters');
    assert(await search.inputValue() === '', 'Reset filters did not clear the search.');
    await visible('All topics');
    assert(!/^0 of/.test(await count.innerText()), 'Reset did not restore available study material.');
    await checkRuntimeMessages();
  });

  await stage('04-required-progress-focused-practice', async () => {
    await openHomeAction('View WSET progress', 'WSET progress');
    await visible('Build knowledge that lasts', startupTimeout);
    await reveal(text('Required study topics'));
    await reveal(text(/^Optional material:/));
    assert(await text('App study milestone complete').count() === 0,
      'Fresh learner incorrectly has a completed app study milestone.');
    await top();
    for (const level of ['WSET Level 1', 'WSET Level 2', 'WSET Level 3']) {
      await reveal(text(level));
      await screenshot(`04-progress-${level.replace(/\W+/g, '-').toLowerCase()}`);
    }
    await top();
    await tap(/^Study requirements · \d+\/\d+ mastered$/);
    await tap(firstL1Requirement.title);
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
    assert(await selected(named('WSET Level 2')), 'Selected track did not survive reload.');
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
    await tap('Ended draft');
    await top();
    await visible('Attempt ended without a score.');
    assert(await text(/^Original practice:/).count() === 0, 'Ended draft was falsely scored.');
    await tap('Choose a new practice attempt');
    await tap('Start Level 2 practice');
    await top();
    const newTimer = await secondsRemaining();
    assert(newTimer > 3500, 'A new rehearsal did not receive a new timer.');
    // History of a finished draft must not replace this running current attempt.
    await navigation('Home');
    await reload();
    await visible('Home', startupTimeout);
    await openHomeAction('Level rehearsal', 'WSET practice');
    assert(await secondsRemaining() > 3400, 'New running rehearsal was not restored.');
  });

  await stage('07-guided-routing-and-saved-evidence', async () => {
    await openHomeAction('Guided tasting and calibration', 'Guided tasting');
    await reveal(text('Observe a physical wine'));
    await tap('Start guided tasting');
    await top();
    await visible('Level 2 · Physical wine observation');
    await visible('Untimed guided practice. This is not the paired tasting examination format.');
    const evidence = page.getByRole('textbox', { name: 'Your evidence' }).first();
    await reveal(evidence);
    await evidence.fill('UI smoke draft: observations need a physical wine and supporting evidence.');
    // Leaving flushes the serialized text writes before showing saved history.
    await tap('Leave this guided session');
    await reveal(text('Saved guided sessions'));
    await navigation('Home');
    await reload();
    await visible('Home', startupTimeout);
    await openHomeAction('Guided tasting and calibration', 'Guided tasting');
    await reveal(text('Saved guided sessions'));
    await tap('Level 2 · Physical wine');
    const restored = page.getByRole('textbox', { name: 'Your evidence' }).first();
    await reveal(restored);
    assert((await restored.inputValue()).startsWith('UI smoke draft:'), 'Guided evidence was not restored.');
    result.assertions.guidedEvidenceRestored = true;
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
    const evidence = page.getByRole('textbox', { name: 'Your evidence' }).first();
    await reveal(evidence);
    await evidence.fill('UI smoke Wine 2 evidence: keep this distinct from Wine 1.');
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
    await reveal(evidence);
    assert((await evidence.inputValue()).startsWith('UI smoke Wine 2 evidence:'), 'Wine 2 evidence lost.');
    await top();
    await tap('Wine 1');
    await reveal(evidence);
    assert(await evidence.inputValue() === '', 'Wine 2 evidence leaked into Wine 1.');
    await tap('Save and finish both wines');
    await top();
    await visible('Pair finished; answers saved.');
    await visible('0 of 2 wines have every required observation and evidence prompt. This records completeness only.');
    await reveal(text(/^Unanswered observations:/));
    await reveal(text(/^Unanswered evidence:/));
    result.assertions.pairedDeadlineRestored = true;
    result.assertions.separatePhysicalWineDrafts = true;
    result.assertions.incompletePairNotGraded = true;
  });

  await stage('09-narrow-main-navigation', async () => {
    for (const destination of ['Home', 'Study', 'Practice', 'Tasting', 'Cellar']) {
      await navigation(destination);
      await checkRuntimeMessages();
      await screenshot(`09-nav-${destination.toLowerCase()}`);
    }
    const bodyOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    assert(!bodyOverflow, 'The page overflows horizontally at 320 pixels.');
    result.assertions.narrowDestinations = 5;
  });
  assert(result.pageErrors.length === 0, `Uncaught browser errors: ${result.pageErrors.join('\n')}`);
  assert(result.consoleErrors.length === 0, `Browser console errors: ${result.consoleErrors.join('\n')}`);
  assert(result.blockedExternalRequests.length === 0,
    `Build attempted external resources: ${result.blockedExternalRequests.join('\n')}`);
  assert(result.failedRequests.length === 0, `Failed requests: ${JSON.stringify(result.failedRequests)}`);
  result.ok = true;
} catch (error) {
  result.failedStage = stageName;
  result.error = error.stack ?? String(error);
  if (page && !page.isClosed()) {
    await screenshot('failure').catch(() => {});
    await page.content().then(html => fs.promises.writeFile(
      path.join(output, 'failure.html'), html)).catch(() => {});
    await page.locator('body').ariaSnapshot().then(snapshot => fs.promises.writeFile(
      path.join(output, 'failure-accessibility.txt'), snapshot)).catch(() => {});
  }
} finally {
  result.finishedAt = new Date().toISOString();
  // Close only the server and browser owned by this run. No port/process kill.
  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
  if (server) await new Promise(resolve => server.close(resolve));
  fs.writeFileSync(path.join(output, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
}
console.log(`APP_UI_SMOKE_RESULT ${JSON.stringify(result)}`);
if (!result.ok) process.exitCode = 1;
