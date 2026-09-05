import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, renameSync, rmSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildPreviews } from './build-brand-preview.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));
const tools = join(project, 'tools');
export const generatedDirectories = ['mono', 'color', 'menubar', 'composer', 'previews'];

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
    // 固定 PDF 创建时间，避免相同输入每次导出产生二进制 diff。
    env: { ...process.env, SOURCE_DATE_EPOCH: '0' }, ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${command}: ${result.error?.message || result.stderr.trim() || `exit ${result.status}, signal ${result.signal}`}`);
  }
  if (result.stderr.trim()) process.stderr.write(result.stderr);
  return result.stdout;
}
function xpath(path, expression) {
  return run('xmllint', ['--nonet', '--xpath', expression, path]).trim();
}
function palettesAt(sources) {
  const palettes = JSON.parse(readFileSync(join(sources, 'palettes.json'), 'utf8'));
  for (const key of ['primary', 'inverse']) {
    if (!(palettes.mono?.[key] === 'currentColor' || /^#[0-9a-f]{6}$/i.test(palettes.mono?.[key] ?? ''))) {
      throw new Error(`palettes.json: mono.${key} must be currentColor or #RRGGBB.`);
    }
  }
  for (const theme of ['light', 'dark']) {
    for (const layer of ['waves', 'orb']) {
      if (!/^#[0-9a-f]{6}$/i.test(palettes.themes?.[theme]?.[layer] ?? '')) {
        throw new Error(`palettes.json: themes.${theme}.${layer} must be #RRGGBB.`);
      }
    }
  }
  return palettes;
}
export function transformSVG(source, { size = 1024, waves = 'currentColor', orb = 'currentColor', layer = 'all' } = {}) {
  return run('xsltproc', [
    '--nonet', '--novalid',
    ...Object.entries({ size, waves, orb, layer }).flatMap(([key, value]) => ['--stringparam', key, String(value)]),
    join(tools, 'brand-transform.xsl'), source,
  ]);
}
function validateSource(path) {
  const content = readFileSync(path, 'utf8');
  if (/<!DOCTYPE|<!ENTITY/.test(content)) throw new Error(`${path}: self-contained SVG must not use DTDs or entities.`);
  // XML 由系统解析器处理；数值这里只检查画布，不读取任何路径坐标。
  const viewBox = xpath(path, 'string(/*/@viewBox)').split(/[\s,]+/).map(Number);
  if (viewBox.length !== 4 || !viewBox.every(Number.isFinite) || viewBox[2] <= 0 || viewBox[3] <= 0) {
    throw new Error(`${path}: viewBox must contain four finite numbers with positive dimensions.`);
  }
  transformSVG(path); // XSLT 同时检查图层、颜色与自包含约束。
}
function render(svg, output, size, format = 'png') {
  const length = format === 'pdf' ? `${size}pt` : String(size);
  run('rsvg-convert', [
    `--format=${format}`, '--keep-aspect-ratio',
    `--width=${length}`, `--height=${length}`,
    `--page-width=${length}`, `--page-height=${length}`,
    '--output', output, svg,
  ]);
}

export function buildBrand({ sources = join(project, 'brand/sources'), output = join(project, 'brand') } = {}) {
  const version = run('rsvg-convert', ['--version']).split('\n')[0];
  const palettes = palettesAt(sources);
  for (const name of ['solid', 'outline', 'menubar']) validateSource(join(sources, `${name}.svg`));
  const firstLayer = xpath(join(sources, 'solid.svg'), 'string(/*/*[local-name()="g"][1]/@id)');
  const layerOrder = firstLayer === 'waves' ? ['waves', 'orb'] : ['orb', 'waves'];

  const cache = join(project, '.build');
  mkdirSync(cache, { recursive: true });
  const work = mkdtempSync(join(cache, 'brand-export-'));
  const stage = join(work, 'assets');
  mkdirSync(stage);
  const exportAsset = (master, stem, ink, { layer = 'all', size = 1024, pdf = true } = {}) => {
    const path = join(stage, stem);
    mkdirSync(resolve(path, '..'), { recursive: true });
    writeFileSync(`${path}.svg`, transformSVG(join(sources, `${master}.svg`), { ...ink, layer, size }));
    render(`${path}.svg`, `${path}.png`, size);
    if (pdf) render(`${path}.svg`, `${path}.pdf`, master === 'menubar' ? 18 : 256, 'pdf');
  };
  try {
    for (const master of ['solid', 'outline']) {
      for (const [key, suffix] of [['primary', ''], ['inverse', '-white']]) {
        const ink = palettes.mono[key];
        exportAsset(master, `mono/${master}${suffix}`, { waves: ink, orb: ink });
      }
    }
    for (const theme of ['light', 'dark']) {
      const ink = palettes.themes[theme];
      exportAsset('solid', `color/${theme}`, ink);
      for (const layer of ['waves', 'orb']) exportAsset('solid', `composer/${theme}/${layer}`, ink, { layer, pdf: false });
    }
    // Template 的纯黑是系统格式约束，不参与品牌配色。
    exportAsset('menubar', 'menubar/TideBarTemplate', { waves: '#000000', orb: '#000000' }, { size: 18 });
    render(join(stage, 'menubar/TideBarTemplate.svg'), join(stage, 'menubar/TideBarTemplate@2x.png'), 36);
    buildPreviews(stage, palettes);
    for (const name of ['mono', 'color']) render(join(stage, `previews/${name}.svg`), join(stage, `previews/${name}.png`), 1200);
    const moduleCache = join(cache, 'brand-module-cache');
    mkdirSync(moduleCache, { recursive: true });
    const result = run('swift', ['-module-cache-path', moduleCache, join(tools, 'verify-brand.swift'), stage, layerOrder.join(',')]);
    process.stdout.write(result);
    // 全部生成并验证后才发布。出错时恢复已有成品，母版与说明从不参与替换。
    mkdirSync(output, { recursive: true });
    const published = [], backups = [];
    try {
      for (const directory of generatedDirectories) {
        const destination = join(output, directory), backup = join(work, directory);
        if (existsSync(destination)) {
          renameSync(destination, backup);
          backups.push(directory);
        }
        renameSync(join(stage, directory), destination);
        published.push(directory);
      }
    } catch (error) {
      for (const directory of published) rmSync(join(output, directory), { recursive: true, force: true });
      for (const directory of backups) renameSync(join(work, directory), join(output, directory));
      throw error;
    }
    console.log(`Generated all brand assets and both previews with ${version}.`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { buildBrand(); }
  catch (error) {
    console.error(`Brand export failed: ${error.message}`);
    process.exitCode = 1;
  }
}
