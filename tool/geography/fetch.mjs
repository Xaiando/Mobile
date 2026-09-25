// Downloads every source of sources.yaml into the cache, checks its SHA-256
// and unpacks archives, so that build and check then run offline
// (docs/design/geography.md §7).
//
//   npm run fetch              download what is missing, then verify all
//   npm run fetch -- --record  record the SHA-256 of sources marked PENDING
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import sevenBin from '7zip-bin';
import {
  cacheDir,
  downloadPath,
  hashOf,
  isArchive,
  loadConfig,
  toolDir,
  unpackedDir,
} from './lib.mjs';

const record = process.argv.includes('--record');

/** Downloads [url] to [file], resuming a partial download on each retry. */
async function download(url, file) {
  const part = `${file}.part`;
  for (let attempt = 1; attempt <= 6; attempt++) {
    const have = fs.existsSync(part) ? fs.statSync(part).size : 0;
    try {
      const response = await fetch(url, {
        headers: have > 0 ? { Range: `bytes=${have}-` } : {},
        redirect: 'follow',
      });
      if (response.status !== 200 && response.status !== 206) {
        throw new Error(`HTTP ${response.status}`);
      }
      // A server that ignores the range sends the whole file again.
      const append = response.status === 206;
      await pipeline(
        Readable.fromWeb(response.body),
        fs.createWriteStream(part, { flags: append ? 'a' : 'w' }),
      );
      fs.renameSync(part, file);
      return;
    } catch (error) {
      console.log(`  attempt ${attempt} failed (${error.message})`);
      await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
    }
  }
  throw new Error(`could not download ${url}`);
}

/** Unpacks [source]'s archive once per SHA-256. */
function unpack(source) {
  const dir = unpackedDir(source);
  const stamp = path.join(dir, '.sha256');
  if (fs.existsSync(stamp) && fs.readFileSync(stamp, 'utf8') === source.sha256) {
    return;
  }
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  if (process.platform !== 'win32') fs.chmodSync(sevenBin.path7za, 0o755);
  execFileSync(sevenBin.path7za, [
    'x',
    downloadPath(source),
    `-o${dir}`,
    '-y',
    '-bso0',
    '-bsp0',
  ]);
  fs.writeFileSync(stamp, source.sha256);
}

/** Writes [hash] in place of [id]'s PENDING SHA-256 in sources.yaml. */
function recordHash(id, hash) {
  const file = path.join(toolDir, 'sources.yaml');
  const text = fs.readFileSync(file, 'utf8');
  const start = text.indexOf(`- id: ${id}\n`) >= 0
    ? text.indexOf(`- id: ${id}\n`)
    : text.indexOf(`- id: ${id}\r\n`);
  const at = text.indexOf('sha256: PENDING', start);
  fs.writeFileSync(
    file,
    `${text.slice(0, at)}sha256: ${hash}${text.slice(at + 'sha256: PENDING'.length)}`,
  );
}

const { sources } = loadConfig();
fs.mkdirSync(cacheDir, { recursive: true });
let failed = false;
for (const source of sources.values()) {
  const file = downloadPath(source);
  if (!fs.existsSync(file)) {
    console.log(`Downloading ${source.id}: ${source.url}`);
    await download(source.url, file);
  }
  const actual = await hashOf(file);
  if (source.sha256 === 'PENDING') {
    if (!record) {
      console.log(
        `${source.id}: SHA-256 ${actual}; record it with npm run fetch -- --record`,
      );
      failed = true;
      continue;
    }
    recordHash(source.id, actual);
    source.sha256 = actual;
    console.log(`${source.id}: recorded SHA-256 ${actual}`);
  } else if (actual !== source.sha256) {
    console.log(
      `${source.id}: the download's SHA-256 is ${actual}, not ${source.sha256}. ` +
        `If the publisher changed the file, record the new edition; otherwise ` +
        `delete ${file} and fetch again.`,
    );
    failed = true;
    continue;
  }
  if (isArchive(source)) unpack(source);
  console.log(`ok  ${source.id}`);
}
console.log(`Cache: ${cacheDir}`);
process.exit(failed ? 1 : 0);
