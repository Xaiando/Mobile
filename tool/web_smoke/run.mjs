// Serves a web build of tool/web_smoke/main.dart and checks the database in
// headless Chromium, once without and once with cross-origin isolation
// (COOP/COEP), which changes the storage Drift can use.
//
//   flutter build web -t tool/web_smoke/main.dart -o build/web_smoke --no-web-resources-cdn
//   node tool/web_smoke/run.mjs build/web_smoke
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)('playwright');

const root = path.resolve(process.argv[2] ?? 'build/web_smoke');
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.otf': 'font/otf', '.ttf': 'font/ttf',
};

const expected = {
  foreignKeys: 1,
  schemaVersion: 2,
  json: 1,
  curriculum: 'installed',
  chablisAncestors: 'Burgundy > France',
  mcqOptions: 4,
  mcqAnswerShown: true,
  sessionCards: 5,
  reviewRating: 3,
  reviewState: 1,
  reviewStored: true,
  reviewEventId: true,
  studied: 1,
  curriculumWriteOutsideLock: 'rejected',
  curriculumWriteInsideLock: 'accepted',
  utcTimestamp: 'accepted',
  localTimestamp: 'rejected',
  durability: 'persistent',
};

function serve(port, isolated) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let file = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      if (file.endsWith('/')) file += 'index.html';
      const full = path.join(root, file);
      if (!full.startsWith(root) || !fs.existsSync(full)) {
        res.writeHead(404);
        res.end();
        return;
      }
      const headers = { 'Content-Type': types[path.extname(full)] ?? 'application/octet-stream' };
      if (isolated) {
        headers['Cross-Origin-Opener-Policy'] = 'same-origin';
        headers['Cross-Origin-Embedder-Policy'] = 'require-corp';
      }
      res.writeHead(200, headers);
      fs.createReadStream(full).pipe(res);
    }).listen(port, () => resolve(server));
  });
}

const browser = await chromium.launch();
let failures = 0;
for (const [port, isolated] of [[8631, false], [8632, true]]) {
  const server = await serve(port, isolated);
  const page = await browser.newPage({ locale: 'en-US' });
  let result;
  const errors = [];
  page.on('console', (message) => {
    const text = message.text();
    if (text.startsWith('SMOKE_RESULT ')) result = JSON.parse(text.slice(13));
  });
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(`http://localhost:${port}/`);
  for (let i = 0; i < 120 && !result; i++) await page.waitForTimeout(250);

  const label = `COOP/COEP ${isolated ? 'on' : 'off'}`;
  const problems = [...errors.map((e) => `page error: ${e}`)];
  if (!result) problems.push('no SMOKE_RESULT within 30 s');
  else {
    if (result.error) problems.push(`error: ${result.error}`);
    for (const [key, value] of Object.entries(expected)) {
      if (result[key] !== value) problems.push(`${key}: expected ${value}, got ${result[key]}`);
    }
    // The bundle loads only if every file its manifest includes was bundled,
    // and the release installed must be the one bundled.
    if (!/^\d+\.\d+\.\d+$/.test(result.bundle ?? '')) {
      problems.push(`bundle: expected a release version, got ${result.bundle}`);
    } else if (result.release !== result.bundle) {
      problems.push(`release: expected ${result.bundle}, got ${result.release}`);
    }
    // Spec TASK-002: at least 50 nodes and 50 edges after initialization.
    for (const key of ['nodes', 'relations']) {
      if (!(result[key] >= 50)) problems.push(`${key}: expected at least 50, got ${result[key]}`);
    }
    if (!(result.questions > 0)) problems.push(`questions: expected some, got ${result.questions}`);
  }
  console.log(`${problems.length ? 'FAIL' : 'ok  '} ${label}: ${JSON.stringify(result)}`);
  for (const problem of problems) console.log(`     ${problem}`);
  failures += problems.length ? 1 : 0;
  await page.close();
  server.close();
}
await browser.close();
process.exit(failures ? 1 : 0);
