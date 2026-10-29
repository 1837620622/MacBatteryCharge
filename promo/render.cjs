// 逐帧渲染宣传片：每一帧都由 index.html 里的 render(t) 决定，结果可重复。
// 用法：node render.cjs <zh|en> <输出目录> [fps] [只截这一秒，用于检查排版]
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const { mkdirSync } = require('node:fs');
const { resolve } = require('node:path');
const { pathToFileURL } = require('node:url');

async function main() {
  const here = __dirname;
  const lang = process.argv[2] || 'zh';
  const outDir = resolve(process.argv[3] || 'out');
  const fps = Number(process.argv[4] || 30);
  const probe = process.argv[5] ? Number(process.argv[5]) : null;

  mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(resolve(here, 'index.html')).href + `?lang=${lang}`);
  await page.waitForFunction(() => window.ready === true);
  await page.evaluate(() => document.fonts.ready);
  const duration = await page.evaluate(() => window.DURATION);

  if (probe !== null) {
    const shot = resolve(outDir, `probe-${lang}-${probe}.png`);
    await page.evaluate(t => window.render(t), probe);
    await page.screenshot({ path: shot });
    console.log('probe', shot);
    await browser.close();
    return;
  }

  const frames = Math.round(duration * fps);
  for (let f = 0; f < frames; f++) {
    const t = f / fps;
    await page.evaluate(t => window.render(t), t);
    await page.screenshot({ path: resolve(outDir, `frame_${String(f).padStart(5, '0')}.png`) });
    if (f % 150 === 0) console.log(`frame ${f}/${frames}`);
  }
  await browser.close();

  const mp4 = resolve(here, `charge-limit-promo-${lang}.mp4`);
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps),
    '-i', resolve(outDir, 'frame_%05d.png'), '-c:v', 'libx264', '-preset', 'slow', '-crf', '18',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4], { stdio: 'inherit' });
  console.log('wrote', mp4);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
