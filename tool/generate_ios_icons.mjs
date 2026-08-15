import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { Resvg } from '@resvg/resvg-js';

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const appIconDir = resolve(rootDir, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const contentsJson = JSON.parse(readFileSync(resolve(appIconDir, 'Contents.json'), 'utf8'));

const svgPath = resolve(rootDir, '../myapp/public/icon.svg');
const svgBlack = readFileSync(svgPath, 'utf8');
const svgWhite = svgBlack.replace(/stroke=\"#000000\"/g, 'stroke=\"#FFFFFF\"');

const rendererWidth = 4096;
const blackRenderer = new Resvg(svgBlack, {
  fitTo: { mode: 'width', value: rendererWidth },
  background: 'rgba(0,0,0,0)',
});
const rawBlackTrimmed = await sharp(blackRenderer.render().asPng()).trim().png().toBuffer();

const whiteRenderer = new Resvg(svgWhite, {
  fitTo: { mode: 'width', value: rendererWidth },
  background: 'rgba(0,0,0,0)',
});
const rawWhiteTrimmed = await sharp(whiteRenderer.render().asPng()).trim().png().toBuffer();

const PNG_OPTIONS = {
  compressionLevel: 6,
  adaptiveFiltering: true,
};
const TRANSPARENT = { r: 0, g: 0, b: 0, alpha: 0 };
const WHITE_BG = { r: 255, g: 255, b: 255, alpha: 1 };

const targetWidthMap = {
  'AppIcon.png': 839,
  'StoreIcon.png': 839,
  'DarkIcon.png': 839,
  'TintedIcon.png': 839,
  'AppIcon-20@2x.png': 32,
  'AppIcon-20@2x~ipad.png': 32,
  'AppIcon-20@3x.png': 48,
  'AppIcon-20~ipad.png': 16,
  'AppIcon-29.png': 23,
  'AppIcon-29@2x.png': 46,
  'AppIcon-29@2x~ipad.png': 46,
  'AppIcon-29@3x.png': 71,
  'AppIcon-29~ipad.png': 23,
  'AppIcon-40@2x.png': 65,
  'AppIcon-40@2x~ipad.png': 65,
  'AppIcon-40@3x.png': 98,
  'AppIcon-40~ipad.png': 32,
  'AppIcon-60@2x~car.png': 98,
  'AppIcon-60@3x~car.png': 147,
  'AppIcon-83.5@2x~ipad.png': 137,
  'AppIcon@2x.png': 98,
  'AppIcon@2x~ipad.png': 124,
  'AppIcon@3x.png': 147,
  'AppIcon~ipad.png': 62,
};

async function generateEntry(image) {
  const filename = image.filename;
  if (!filename) return;

  const [baseWidth, baseHeight] = image.size.split('x').map(Number);
  const scale = Number.parseInt(image.scale.replace('x', ''), 10) || 1;
  const canvasW = Math.round(baseWidth * scale);
  const canvasH = Math.round(baseHeight * scale);

  const isWhite = filename.includes('DarkIcon') || filename.includes('TintedIcon');
  const src = isWhite ? rawWhiteTrimmed : rawBlackTrimmed;
  const targetW = targetWidthMap[filename] || Math.round(canvasW * 0.8193);

  const resized = await sharp(src)
    .resize(targetW, null, { fit: 'inside', background: TRANSPARENT, kernel: 'lanczos3' })
    .sharpen({ sigma: 0.4, m1: 0.6, m2: 0.02 })
    .png(PNG_OPTIONS)
    .toBuffer();

  const outPath = resolve(appIconDir, filename);

  if (isWhite) {
    await sharp({
      create: {
        width: canvasW,
        height: canvasH,
        channels: 4,
        background: TRANSPARENT,
      },
    })
      .composite([{ input: resized, gravity: 'center' }])
      .png(PNG_OPTIONS)
      .toFile(outPath);
    return;
  }

  await sharp({
    create: {
      width: canvasW,
      height: canvasH,
      channels: 4,
      background: WHITE_BG,
    },
  })
    .composite([{ input: resized, gravity: 'center' }])
    .removeAlpha()
    .png(PNG_OPTIONS)
    .toFile(outPath);
}

const main = async () => {
  for (const image of contentsJson.images) {
    await generateEntry(image);
  }
  console.info('iOS app icons generated successfully');
};

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
