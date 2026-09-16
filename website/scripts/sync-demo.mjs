// 把应用资源目录的演示视频同步到网站 public/：
// 真值只有 Sources/TideBar/Resources/onboarding-demo.mp4 一份，
// 本脚本产物是构建副本，不进 git（见 .gitignore）。
import { copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
await copyFile(
  resolve(root, "Sources/TideBar/Resources/onboarding-demo.mp4"),
  resolve(root, "website/public/demo.mp4"),
);
console.log("synced demo.mp4 -> website/public/demo.mp4");
