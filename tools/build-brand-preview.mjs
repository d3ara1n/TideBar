import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const text = (x, y, value, size = 14, color = '#72757d') =>
  `<text x="${x}" y="${y}" font-family="Helvetica Neue, Arial, sans-serif" font-size="${size}" fill="${color}">${escape(value)}</text>`;

// 用独立的 SVG image 文档嵌入，保留母版根属性，并隔离各实例的 ID / 裁剪引用。
export function buildPreviews(root, palettes) {
  const image = (path, x, y, size, filter = '') => {
    const mime = path.endsWith('.svg') ? 'image/svg+xml' : 'image/png';
    const data = readFileSync(join(root, path)).toString('base64');
    return `<image x="${x}" y="${y}" width="${size}" height="${size}" href="data:${mime};base64,${data}"${filter ? ` filter="url(#${filter})"` : ''}/>`;
  };
  const start = (title, description) => [
    '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">',
    '<rect width="1200" height="1200" fill="#e9eaed"/>',
    text(40, 46, title, 26, '#191b22'), text(40, 75, description, 15),
  ];
  mkdirSync(join(root, 'previews'), { recursive: true });
  const save = (name, parts) => writeFileSync(join(root, `previews/${name}.svg`), [...parts, '</svg>'].join('\n') + '\n');

  const mono = start('TideBar / Monochrome marks', 'Original vector artwork · Transparent wave cutouts · No app-icon background');
  for (const [row, variant] of ['solid', 'outline'].entries()) {
    for (const [column, dark] of [false, true].entries()) {
      const x = 24 + column * 588, y = 102 + row * 500;
      const fg = dark ? '#f4f5f7' : '#191b22', muted = dark ? '#a8acb6' : '#72757d';
      const path = `mono/${variant}${dark ? '-white' : ''}.svg`;
      mono.push(`<rect x="${x}" y="${y}" width="564" height="482" rx="16" fill="${dark ? '#191b22' : '#ffffff'}"/>`);
      mono.push(text(x + 24, y + 34, variant === 'solid' ? 'A / Solid orb' : 'B / Outline orb', 18, fg));
      mono.push(text(x + 420, y + 34, dark ? 'DARK' : 'LIGHT', 12, muted));
      mono.push(image(path, x + 162, y + 54, 240));
      for (const [index, size] of [16, 18, 32, 64, 128].entries()) {
        const center = x + [58, 148, 242, 346, 470][index];
        mono.push(image(path, center - size / 2, y + 374 - size / 2, size));
        mono.push(text(center - 14, y + 453, `${size}px`, 12, muted));
      }
    }
  }
  mono.push(text(40, 1140, 'Standard marks at 100%. The optical-size menu-bar template is shown in the color comparison.'));
  save('mono', mono);

  const color = start('TideBar / Sea & Sky', 'Solid-color artwork · Transparent backgrounds · No baked-in lighting or shadows');
  for (const [column, theme] of ['light', 'dark'].entries()) {
    const x = 24 + column * 588, dark = theme === 'dark';
    const fg = dark ? '#f4f5f7' : '#191b22', muted = dark ? '#a8acb6' : '#72757d';
    color.push(`<rect x="${x}" y="102" width="564" height="570" rx="16" fill="${dark ? '#191b22' : '#ffffff'}"/>`);
    color.push(text(x + 24, 140, dark ? 'Dark / Moonlit water' : 'Light / Sunlit water', 18, fg));
    color.push(image(`color/${theme}.svg`, x + 122, 152, 320));
    for (const [index, size] of [32, 64, 128].entries()) {
      const center = x + [98, 260, 448][index];
      color.push(image(`color/${theme}.svg`, center - size / 2, 524 - size / 2, size));
      color.push(text(center - 16, 605, `${size}px`, 12, muted));
    }
    color.push(text(x + 24, 645, `SEA ${palettes.themes[theme].waves}     ORB ${palettes.themes[theme].orb}`, 13, muted));
  }
  color.push('<rect x="24" y="692" width="1152" height="420" rx="16" fill="#ffffff"/>');
  color.push(text(48, 732, 'Menu bar / Optical-size template', 18, '#191b22'));
  color.push(text(48, 760, '18pt canvas · Stronger strokes · Tighter framing · System-controlled color'));
  color.push('<defs><filter id="white-template" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 1 0"/></filter></defs>');
  for (const [index, dark] of [false, true].entries()) {
    const x = 48 + index * 552;
    color.push(`<rect x="${x}" y="792" width="504" height="68" rx="10" fill="${dark ? '#191b22' : '#eff0f3'}"/>`);
    for (const [i, file] of ['TideBarTemplate.png', 'TideBarTemplate@2x.png'].entries()) {
      color.push(image(`menubar/${file}`, x + 76 + i * 192, 817, 18, dark ? 'white-template' : ''));
      color.push(text(x + 108 + i * 192, 831, i === 0 ? '1×' : '2×', 12, dark ? '#a8acb6' : '#72757d'));
    }
  }
  color.push(image('menubar/TideBarTemplate.svg', 100, 884, 144));
  color.push(text(270, 952, 'Template silhouette / 8×'));
  color.push(image('mono/solid.svg', 610, 884, 144));
  color.push(image('mono/outline.svg', 854, 884, 144));
  color.push(text(630, 1058, 'Primary / Solid', 13));
  color.push(text(870, 1058, 'Alternate / Outline', 13));
  color.push(text(40, 1155, 'The monochrome comparison is available as previews/mono.svg and mono.png.'));
  save('color', color);
}
