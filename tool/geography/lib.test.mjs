// Unit tests of the pipeline's shared rules (npm test): the licence gate,
// cache verification and layer attributions.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';

const cache = fs.mkdtempSync(path.join(os.tmpdir(), 'geography-cache-'));
process.env.SOMMELIER_GEO_CACHE = cache;
const { cacheState, isOpenLicence, layerAttribution, sha256, unpackedDir } =
  await import('./lib.mjs');
after(() => fs.rmSync(cache, { recursive: true, force: true }));

test('the licence gate admits only licences that allow bundling (GEO-5)', () => {
  for (const licence of [
    'Public domain',
    'CC0 1.0',
    'CC0 1.0 Universal',
    'CC BY 4.0',
    'CC BY 4.0 International',
    'Licence Ouverte / Open Licence 2.0 (Etalab)',
    'Licence Ouverte 2.0',
    'Datenlizenz Deutschland – Namensnennung – Version 2.0',
    'Datenlizenz Deutschland – Zero – Version 2.0',
  ]) {
    assert.ok(isOpenLicence(licence), licence);
  }
  for (const licence of [
    'CC BY-NC 4.0',
    'CC BY-NC-SA 4.0',
    'CC BY-NC-ND 4.0',
    'CC BY-SA 4.0',
    'CC BY-ND 4.0',
    'ODbL 1.0',
    'Datenlizenz Deutschland – Namensnennung – nicht kommerziell – Version 1.0',
    'All rights reserved',
    '',
  ]) {
    assert.ok(!isOpenLicence(licence), licence);
  }
});

test('a cached download counts only as the edition sources.yaml records', async () => {
  const source = { id: 'src_test_csv', file: 'test.csv', sha256: sha256('a;b\n') };
  assert.equal(await cacheState(source), 'missing');
  fs.writeFileSync(path.join(cache, 'test.csv'), 'a;b\n');
  assert.equal(await cacheState(source), 'ok');
  fs.writeFileSync(path.join(cache, 'test.csv'), 'a;c\n');
  assert.equal(await cacheState(source), 'stale');
});

test('an archive counts by the edition its files were unpacked from', async () => {
  const source = { id: 'src_test_zip', file: 'test.zip', sha256: 'a'.repeat(64) };
  fs.writeFileSync(path.join(cache, 'test.zip'), 'zip');
  assert.equal(await cacheState(source), 'missing', 'downloaded, not unpacked');
  const stamp = path.join(unpackedDir(source), '.sha256');
  fs.mkdirSync(path.dirname(stamp), { recursive: true });
  fs.writeFileSync(stamp, 'b'.repeat(64));
  assert.equal(await cacheState(source), 'stale');
  fs.writeFileSync(stamp, 'a'.repeat(64));
  assert.equal(await cacheState(source), 'ok');
});

test('a layer shows each attribution of its sources once, in order', () => {
  const config = {
    sources: new Map([
      ['src_a', { attribution: 'A.' }],
      ['src_b', { attribution: 'B.' }],
      ['src_c', { attribution: 'A.' }],
    ]),
  };
  assert.equal(layerAttribution(config, { sources: ['src_a', 'src_b', 'src_c'] }), 'A. B.');
});
