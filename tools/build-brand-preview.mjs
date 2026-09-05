import { readFileSync, writeFileSync } from 'node:fs';

const root = new URL('../brand/', import.meta.url);
let serial = 0;
function mark(path, x, y, size, color) {
  const source = readFileSync(new URL(path, root), 'utf8');
  const box = source.match(/viewBox="([^"]+)"/)[1];
  const ids = [...source.matchAll(/id="([^"]+)"/g)].map(match => match[1]);
  let body = source.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/<title>.*?<\/title>/, '');
  for (const id of ids) body = body.replaceAll(id, `preview-${serial++}`);
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${box}" fill="none" color="${color ?? '#191b22'}">${body}</svg>`;
}
function text(x, y, value, size = 14, color = '#72757d') {
  return `<text x="${x}" y="${y}" font-family="Helvetica Neue, Arial, sans-serif" font-size="${size}" fill="${color}">${value}</text>`;
}
const parts = [
  '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">',
  '<rect width="1200" height="1200" fill="#e9eaed"/>',
  text(40, 46, 'TideBar / Sea &amp; Sky', 26, '#191b22'),
  text(40, 75, 'Solid-color artwork · Transparent backgrounds · No baked-in lighting or shadows', 15),
];
for (const [column, theme] of ['light', 'dark'].entries()) {
  const x = 24 + column * 588;
  const dark = theme === 'dark';
  const fg = dark ? '#f4f5f7' : '#191b22';
  const muted = dark ? '#a8acb6' : '#72757d';
  parts.push(`<rect x="${x}" y="102" width="564" height="570" rx="16" fill="${dark ? '#191b22' : '#ffffff'}"/>`);
  parts.push(text(x + 24, 140, dark ? 'Dark / Moonlit water' : 'Light / Sunlit water', 18, fg));
  parts.push(mark(`color/${theme}.svg`, x + 122, 152, 320));
  for (const [i, size] of [32, 64, 128].entries()) {
    const center = x + [98, 260, 448][i];
    parts.push(mark(`color/${theme}.svg`, center - size / 2, 524 - size / 2, size));
    parts.push(text(center - 16, 605, `${size}px`, 12, muted));
  }
  parts.push(text(x + 24, 645, dark ? 'SEA #65CADD     ORB #F5D69A' : 'SEA #167D9A     ORB #F2AE49', 13, muted));
}
parts.push('<rect x="24" y="692" width="1152" height="420" rx="16" fill="#ffffff"/>');
parts.push(text(48, 732, 'Menu bar / Optical-size template', 18, '#191b22'));
parts.push(text(48, 760, '18pt canvas · Stronger strokes · Tighter framing · System-controlled color', 14));
// PNG 检查实际 1× / 2× 栅格，SVG 展示放大的轮廓。
for (const [index, dark] of [false, true].entries()) {
  const x = 48 + index * 552;
  parts.push(`<rect x="${x}" y="792" width="504" height="68" rx="10" fill="${dark ? '#191b22' : '#eff0f3'}"/>`);
  for (const [i, filename] of ['TideBarTemplate.png', 'TideBarTemplate@2x.png'].entries()) {
    const data = readFileSync(new URL(`menubar/${filename}`, root)).toString('base64');
    // 白色展示只是预览；模板源文件始终为黑色透明。
    parts.push(`<image x="${x + 76 + i * 192}" y="817" width="18" height="18" href="data:image/png;base64,${data}"${dark ? ' filter="url(#white-template)"' : ''}/>`);
    parts.push(text(x + 108 + i * 192, 831, i === 0 ? '1×' : '2×', 12, dark ? '#a8acb6' : '#72757d'));
  }
}
parts.push('<defs><filter id="white-template" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 1 0"/></filter></defs>');
parts.push(mark('menubar/TideBarTemplate.svg', 100, 884, 144));
parts.push(text(270, 952, 'Template silhouette / 8×', 14));
parts.push(mark('mono/solid.svg', 610, 884, 144));
parts.push(mark('mono/outline.svg', 854, 884, 144));
parts.push(text(630, 1058, 'Primary / Solid', 13));
parts.push(text(870, 1058, 'Alternate / Outline', 13));
parts.push(text(40, 1155, 'The original monochrome comparison is preserved separately as previews/mono.svg and mono.png.', 14));
parts.push('</svg>');
writeFileSync(new URL('previews/color.svg', root), parts.join('\n') + '\n');
