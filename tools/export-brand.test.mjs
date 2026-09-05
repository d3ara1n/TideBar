import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildBrand, generatedDirectories, transformSVG } from './export-brand.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));
function snapshot(root) {
  const result = {};
  function walk(directory) {
    for (const entry of readdirSync(join(root, directory), { withFileTypes: true })) {
      const path = `${directory}/${entry.name}`;
      if (entry.isDirectory()) walk(path);
      else result[path] = createHash('sha256').update(readFileSync(join(root, path))).digest('hex');
    }
  }
  for (const directory of generatedDirectories) walk(directory);
  return result;
}
function changed(before, after, paths) {
  for (const path of paths) assert.notEqual(after[path], before[path], `Expected regenerated content: ${path}`);
}
function unchanged(before, after, paths) {
  for (const path of paths) assert.equal(after[path], before[path], `Unexpected change: ${path}`);
}

test('SVG masters rebuild all derivatives without geometry assumptions', async t => {
  mkdirSync(join(project, '.build'), { recursive: true });
  const work = mkdtempSync(join(project, '.build/brand-tests-'));
  const sources = join(work, 'sources'), output = join(work, 'output');
  execFileSync('/usr/bin/ditto', [join(project, 'brand/sources'), sources]);
  const build = () => buildBrand({ sources, output });
  try {
    build();
    const initial = snapshot(output);
    assert.equal(Object.keys(initial).length, 34);
    await t.test('identical inputs produce identical SVG, PNG, PDF and previews', () => {
      build();
      assert.deepEqual(snapshot(output), initial);
    });
    await t.test('palette changes flow to artwork, layers and preview swatches', () => {
      const path = join(sources, 'palettes.json');
      const palettes = JSON.parse(readFileSync(path, 'utf8'));
      palettes.themes.light.waves = '#234567';
      writeFileSync(path, JSON.stringify(palettes));
      build();
      const after = snapshot(output);
      changed(initial, after, ['color/light.svg', 'color/light.png', 'color/light.pdf', 'composer/light/waves.svg', 'composer/light/waves.png', 'previews/color.svg', 'previews/color.png']);
      unchanged(initial, after, ['color/dark.png', 'mono/solid.png', 'composer/light/orb.png', 'previews/mono.svg', 'previews/mono.png', 'menubar/TideBarTemplate.pdf']);
      assert.match(readFileSync(join(output, 'previews/color.svg'), 'utf8'), /SEA #234567/);
    });
    await t.test('replacement geometry, namespace, viewport and reversed overlapping layers work', () => {
      const before = snapshot(output);
      writeFileSync(join(sources, 'solid.svg'), `<s:svg xmlns:s="http://www.w3.org/2000/svg" viewBox="-10 -20 200 160" fill="none" preserveAspectRatio="xMidYMid meet">
        <s:defs><s:clipPath id="crop"><s:rect x="0" y="0" width="150" height="120"/></s:clipPath></s:defs>
        <s:g id="orb" fill="currentColor"><s:path d="M70 20H110V80H70Z"/></s:g>
        <s:g id="waves" fill="currentColor" transform="translate(2 3)" clip-path="url(#crop)"><s:rect x="20" y="10" width="120" height="40"/></s:g>
      </s:svg>`);
      build();
      const after = snapshot(output);
      changed(before, after, ['mono/solid.svg', 'mono/solid.png', 'mono/solid.pdf', 'color/light.png', 'color/dark.pdf', 'composer/light/orb.png', 'composer/dark/waves.png', 'previews/mono.svg', 'previews/mono.png', 'previews/color.svg', 'previews/color.png']);
      unchanged(before, after, ['mono/outline.png', 'menubar/TideBarTemplate.pdf']);
      const result = readFileSync(join(output, 'color/light.svg'), 'utf8');
      assert.match(result, /viewBox="-10 -20 200 160"/);
      assert.match(result, /preserveAspectRatio="xMidYMid meet"/);
      assert.match(result, /transform="translate\(2 3\)"/);
      assert.match(result, /clip-path="url\(#crop\)"/);
      assert.ok(result.indexOf('id="orb"') < result.indexOf('id="waves"'));
    });
    await t.test('outline and menu-bar masters own their derivatives', () => {
      const before = snapshot(output);
      for (const [name, from, to] of [['outline', 'r="35"', 'r="30"'], ['menubar', 'r="42"', 'r="38"']]) {
        const path = join(sources, `${name}.svg`);
        writeFileSync(path, readFileSync(path, 'utf8').replace(from, to));
      }
      build();
      const after = snapshot(output);
      changed(before, after, ['mono/outline.svg', 'mono/outline.png', 'mono/outline.pdf', 'mono/outline-white.png', 'menubar/TideBarTemplate.svg', 'menubar/TideBarTemplate.png', 'menubar/TideBarTemplate@2x.png', 'menubar/TideBarTemplate.pdf', 'previews/mono.png', 'previews/color.png']);
      unchanged(before, after, ['mono/solid.png', 'color/light.pdf', 'composer/dark/orb.png']);
    });
    await t.test('invalid source leaves existing products untouched', () => {
      const before = snapshot(output), path = join(sources, 'solid.svg');
      const valid = readFileSync(path, 'utf8');
      writeFileSync(path, valid.replace('id="orb"', 'id="unknown"'));
      assert.throws(build, /direct child groups/);
      assert.deepEqual(snapshot(output), before);
      writeFileSync(path, valid);
      writeFileSync(join(output, 'mono/stale.png'), 'obsolete generated output');
      build();
      assert.deepEqual(snapshot(output), before);
    });
    await t.test('invalid XML, paint, IDs and references fail explicitly', () => {
      const path = join(sources, 'invalid.svg');
      const solid = readFileSync(join(sources, 'solid.svg'), 'utf8');
      for (const [input, error] of [
        ['<svg>', /Premature end|namespace|parse/i],
        [solid.replace('fill="none"', ''), /root fill/],
        [solid.replace('fill="currentColor"', 'fill="#ff0000"'), /currentColor/],
        [solid.replace('<s:path ', '<s:path id="crop" '), /IDs must be unique/],
        [solid.replace('url(#crop)', 'url(#missing)'), /existing local ID/],
        [solid.replace('url(#crop)', 'url(other.svg#crop)'), /existing local ID/],
        [solid.replace('<s:path ', '<s:use href="#missing"/><s:path '), /existing local ID/],
      ]) {
        writeFileSync(path, input);
        assert.throws(() => transformSVG(path), error);
      }
      const crossLayer = solid.replace('<s:rect x="20"', '<s:use href="#orb"/><s:rect x="20"');
      writeFileSync(path, crossLayer);
      assert.doesNotThrow(() => transformSVG(path));
      assert.throws(() => transformSVG(path, { layer: 'waves' }), /removed Composer layer/);
      const before = snapshot(output);
      writeFileSync(join(sources, 'solid.svg'), crossLayer);
      assert.throws(build, /removed Composer layer/);
      assert.deepEqual(snapshot(output), before);
      writeFileSync(path, solid.replace('url(#crop)', "url('#crop')"));
      assert.doesNotThrow(() => transformSVG(path));
    });
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
