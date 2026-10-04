import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { readCurriculum, readYaml, repoDir, sha256 } from './lib.mjs';

const sample = [
  'plain: first', '  second', 'literal: |-', '  one', '  two',
  'folded: >-', '  alpha', '  beta', "escaped: 'literal\\r\\n'",
  'number: 12.5', 'mapping:', '  revision: 2',
  'sequence:', '  - wine', '  - region', '',
].join('\n');
const ordinary = {
  plain: 'first second', literal: 'one\ntwo', folded: 'alpha beta',
  escaped: 'literal\\r\\n', number: 12.5, mapping: { revision: 2 },
  sequence: ['wine', 'region'],
};
function withFile(t, text) {
  const tempRoot = path.resolve(os.tmpdir());
  const folder = fs.mkdtempSync(path.join(tempRoot, 'geography-yaml-newlines-'));
  t.after(() => {
    const resolved = path.resolve(folder);
    const relative = path.relative(tempRoot, resolved);
    assert.ok(relative && !relative.startsWith('..') && !path.isAbsolute(relative),
      'cleanup must stay within the intended temporary root');
    assert.ok(path.basename(resolved).startsWith('geography-yaml-newlines-'),
      'cleanup must target this test-owned generated directory');
    fs.rmSync(resolved, { recursive: true, force: true });
  });
  const file = path.join(folder, 'input.yaml');
  fs.writeFileSync(file, text, 'utf8');
  return file;
}
for (const [name, breaks] of [['LF', '\n'], ['CRLF', '\r\n'], ['CR', '\r']]) {
  test('readYaml preserves mapping and scalar semantics with ' + name, (t) => {
    const file = withFile(t, sample.replaceAll('\n', breaks));
    const before = fs.readFileSync(file);
    assert.deepEqual(readYaml(file), ordinary);
    assert.deepEqual(fs.readFileSync(file), before, 'reading must not rewrite the source');
  });
}
for (const [name, breaks] of [
  ['two LF breaks', '\n\n'], ['CR followed by CRLF', '\r\r\n'],
  ['two CRLF breaks', '\r\n\r\n'],
]) {
  test('readYaml preserves consecutive-break scalar folding: ' + name, (t) => {
    const file = withFile(t, sample.replaceAll('\n', breaks));
    assert.deepEqual(readYaml(file), {
      ...ordinary, plain: 'first\nsecond', literal: '\none\n\ntwo', folded: '\nalpha\nbeta',
    });
    assert.equal(readYaml(file).escaped, 'literal\\r\\n',
      'normalization must not interpret escaped text as physical line breaks');
  });
}
for (const [name, source] of [
  ['unclosed sequence', 'value: [one, two'],
  ['duplicate mapping key', 'value: one\nvalue: two\n'],
  ['invalid indentation', 'value:\n  child: one\n other: two\n'],
]) {
  test('readYaml retains parser rejection for ' + name, (t) => {
    for (const breaks of ['\n', '\r\n', '\r', '\r\r\n']) {
      const file = withFile(t, source.replaceAll('\n', breaks));
      assert.throws(() => readYaml(file), { name: 'YAMLParseError' });
    }
  });
}
test('curriculum reader consumes actual grape-origin rows without rewriting frozen data', () => {
  const file = path.join(repoDir, 'assets/curriculum/areas/wset_grape_origin_contexts.yaml');
  const before = fs.readFileSync(file);
  const area = readYaml(file);
  assert.equal(area.knowledge_nodes.length, 34);
  assert.equal(area.knowledge_items.length, 17);
  const condrieu = area.knowledge_items.find((item) =>
    item.id === 'ki_wset_origin_condrieu_viognier');
  assert.ok(condrieu, 'the existing cited item must remain represented');
  // CR + CRLF is two breaks, preserving a newline within this plain scalar.
  assert.match(condrieu.assertion_text, /dry example is\naromatic/);
  const curriculum = readCurriculum();
  for (const node of area.knowledge_nodes) {
    assert.deepEqual(curriculum.nodes.get(node.id), node);
  }
  assert.equal(sha256(fs.readFileSync(file)), sha256(before));
});

