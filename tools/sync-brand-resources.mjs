import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  renameSync,
  rmSync,
} from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('../', import.meta.url));
const sourceRoot = join(project, 'brand');
const destination = join(project, 'Sources/TideBar/Resources/Brand');
const resources = [
  ['menubar/TideBarTemplate.pdf', 'TideBarTemplate.pdf'],
  ['color/light.pdf', 'light.pdf'],
  ['color/dark.pdf', 'dark.pdf'],
];

export function syncBrandResources({ source = sourceRoot, target = destination } = {}) {
  const stageRoot = mkdtempSync(join(project, '.build', 'brand-sync-'));
  const staged = join(stageRoot, 'Brand');
  mkdirSync(staged);

  try {
    for (const [relativeSource, relativeTarget] of resources) {
      const sourcePath = join(source, relativeSource);
      if (!existsSync(sourcePath)) throw new Error(`Missing generated asset: ${sourcePath}`);
      copyFileSync(sourcePath, join(staged, relativeTarget));
    }

    mkdirSync(resolve(target, '..'), { recursive: true });
    const backup = join(stageRoot, 'previous');
    if (existsSync(target)) renameSync(target, backup);
    try {
      renameSync(staged, target);
    } catch (error) {
      if (existsSync(backup)) renameSync(backup, target);
      throw error;
    }
    rmSync(backup, { recursive: true, force: true });
    console.log(`Synchronized ${resources.length} brand PDFs into ${target}.`);
  } finally {
    rmSync(stageRoot, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { syncBrandResources(); }
  catch (error) {
    console.error(`Brand resource sync failed: ${error.message}`);
    process.exitCode = 1;
  }
}
