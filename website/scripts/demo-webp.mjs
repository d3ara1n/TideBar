// 把截图/动图转成 Demo 窗口用的 webp：npm run demo:convert -- <输入>
// - png/jpg（⌘⇧4 截图）→ 静态 webp
// - gif（录屏转的动图）→ 动画 webp，可展示潮汐展开
import sharp from "sharp";

const [input, output = "public/demo.webp"] = process.argv.slice(2);
if (!input) {
  console.error("Usage: npm run demo:convert -- <screenshot.png|clip.gif>");
  process.exit(1);
}
const animated = /\.(gif|webp)$/i.test(input);
const info = await sharp(input, { animated, limitInputPixels: false })
  .webp({ quality: 90 })
  .toFile(output);
console.log(`written ${output} (${info.width}x${info.height}, ${Math.round(info.size / 1024)}KB)`);
