// Open Board Format (.obz) export, ported from
// claudeBlast/Services/OBFExporter.swift + OBFModels.swift. See
// ../docs/obf-interop.md for the full spec this follows, including what's
// approximated (grid shape, flattened color, one image set) and what
// doesn't survive (sentence generation, Brown's Stage, etc.) — reading that
// doc before changing this file will save you from re-deriving it.

import { zipStore } from "./zip.js";
import { colorForWordClass, NAVIGATION } from "./color.js";

const OBF_VERSION = "open-board-0.1";
const HOME_TILE_KEY = "home";
const EXT = "ext_blasterai_";

function pageTitle(pageKey) {
  return pageKey
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// OBF pins buttons to a fixed rows x columns grid; our boards reflow. This
// picks one shape at export time — slightly wider than tall, matching a
// landscape tablet layout, which is what most AAC readers assume.
function gridShape(count) {
  if (count <= 0) return { rows: 1, columns: 1 };
  const columns = Math.max(1, Math.ceil(Math.sqrt(count * 1.4)));
  const rows = Math.max(1, Math.ceil(count / columns));
  return { rows, columns };
}

function boardIdFor(pageKey, sceneIdentity) {
  const id = sceneIdentity ? `${sceneIdentity}_${pageKey}` : pageKey;
  return id.replace(/\//g, "_");
}

const FIRST_PARTY_LICENSE = {
  type: "Apache-2.0",
  copyright_notice_url: "https://www.apache.org/licenses/LICENSE-2.0",
  author_name: "BlasterAI",
  author_url: "https://blasterai.app",
  source_url: "https://blasterai.app",
};

// Builds one OBF board (page) plus the button/image lists, injecting a
// synthetic Home button at cell 0 for every non-home page — OBF has no
// equivalent of the app's injected chrome, so without this every sub-board
// would be a one-way trip (docs/obf-interop.md "Home is re-materialised").
function buildBoard({ pageKey, placements, sceneJson, sceneIdentity, vocabByKey, vocabularyClasses, imagePrefix }) {
  const entries = [...placements];
  const hasHomeLink = placements.some((p) => p.link && p.to === sceneJson.homePageKey);
  if (pageKey !== sceneJson.homePageKey && !hasHomeLink) {
    entries.unshift({ key: HOME_TILE_KEY, to: sceneJson.homePageKey, audible: false, link: true });
  }

  const buttons = [];
  const images = [];
  const seenImages = new Set();
  const order = [];

  for (const entry of entries) {
    const vocab = vocabByKey.get(entry.key);
    if (!vocab) continue;

    let loadBoard = null;
    if (entry.link) {
      const targetTitle = pageTitle(entry.to);
      loadBoard = {
        id: boardIdFor(entry.to, sceneIdentity),
        path: `boards/${entry.to}.obf`,
        name: targetTitle,
      };
    }

    if (!seenImages.has(vocab.artKey)) {
      seenImages.add(vocab.artKey);
      images.push({
        id: vocab.artKey,
        path: `images/${vocab.artKey}.png`,
        width: 512,
        height: 512,
        content_type: "image/png",
        license: FIRST_PARTY_LICENSE,
      });
    }

    const accent = loadBoard ? NAVIGATION : colorForWordClass(vocab.wordClass, vocabularyClasses);
    buttons.push({
      id: entry.key,
      label: vocab.label,
      image_id: vocab.artKey,
      // A navigation button travels rather than speaks; same for a
      // non-audible tile — OBF has no "present but silent" concept.
      vocalization: !loadBoard && entry.audible ? vocab.label : undefined,
      background_color: accent,
      border_color: accent,
      load_board: loadBoard || undefined,
      [`${EXT}word_class`]: vocab.wordClass,
      [`${EXT}tile_key`]: vocab.key,
    });
    order.push(entry.key);
  }

  const { rows, columns } = gridShape(order.length);
  const gridOrder = [];
  for (let r = 0; r < rows; r++) {
    const row = [];
    for (let c = 0; c < columns; c++) {
      const i = r * columns + c;
      row.push(i < order.length ? order[i] : null);
    }
    gridOrder.push(row);
  }

  const board = {
    format: OBF_VERSION,
    id: boardIdFor(pageKey, sceneIdentity),
    locale: "en",
    name: pageTitle(pageKey),
    buttons,
    grid: { rows, columns, order: gridOrder },
    images,
    sounds: [],
    [`${EXT}scene_id`]: sceneIdentity || undefined,
    [`${EXT}page_key`]: pageKey,
  };

  return { board, imageKeys: [...seenImages] };
}

// Renders a tile's WebP art (already loaded for the live grid) to PNG bytes
// via an offscreen canvas — OBF readers can't be assumed to decode WebP, and
// this is the one direction where the recipient is explicitly not this app.
async function webpToPng(url) {
  const response = await fetch(url);
  const blob = await response.blob();
  const bitmap = await createImageBitmap(blob);
  const canvas = document.createElement("canvas");
  canvas.width = 512;
  canvas.height = 512;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(bitmap, 0, 0, 512, 512);
  const pngBlob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
  return new Uint8Array(await pngBlob.arrayBuffer());
}

// manifest.json — root board written first, matching OBFManifest.jsonData().
// Key order matters here: some readers (Cboard) ignore `root` entirely and
// open whichever board their zip-decompression race finishes first, which
// tends to correlate with archive/file order — see docs/obf-interop.md.
function manifestJson({ rootPath, boardOrder, boardPaths, imagePaths }) {
  const ids = [...boardOrder.filter((id) => boardPaths[id]),
    ...Object.keys(boardPaths).filter((id) => !boardOrder.includes(id)).sort()];
  const boards = {};
  for (const id of ids) boards[id] = boardPaths[id];
  const images = {};
  for (const key of Object.keys(imagePaths).sort()) images[key] = imagePaths[key];
  return JSON.stringify({ format: OBF_VERSION, root: rootPath, paths: { boards, images } }, null, 2);
}

// Exports the whole scene as a .obz Blob. `onProgress(done, total)` reports
// image-conversion progress, the slow part.
export async function exportSceneAsOBZ({ sceneJson, scene, vocabByKey, vocabularyClasses, imagePrefix, onProgress }) {
  const sceneIdentity = sceneJson.key || "";
  const pageKeys = [...scene.keys()];
  // Home board first, matching upstream's archive ordering rationale.
  pageKeys.sort((a, b) => (a === sceneJson.homePageKey ? -1 : b === sceneJson.homePageKey ? 1 : 0));

  const boards = [];
  const allImageKeys = new Set();
  for (const pageKey of pageKeys) {
    const { board, imageKeys } = buildBoard({
      pageKey,
      placements: scene.get(pageKey),
      sceneJson,
      sceneIdentity,
      vocabByKey,
      vocabularyClasses,
      imagePrefix,
    });
    boards.push(board);
    for (const k of imageKeys) allImageKeys.add(k);
  }

  const entries = [];
  const boardPaths = {};
  for (const board of boards) {
    const pageKey = board[`${EXT}page_key`];
    const path = `boards/${pageKey}.obf`;
    entries.push({ path, data: new TextEncoder().encode(JSON.stringify(board, null, 2)) });
    boardPaths[board.id] = path;
  }

  const imageKeys = [...allImageKeys];
  const imagePaths = {};
  const total = imageKeys.length;
  let done = 0;
  onProgress?.(0, total);

  // Converted concurrently (small batches) — sequential fetch+decode+encode
  // for ~500 images is slow enough to feel broken.
  const CONCURRENCY = 8;
  for (let i = 0; i < imageKeys.length; i += CONCURRENCY) {
    const batch = imageKeys.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map((key) => webpToPng(`assets/tiles/${imagePrefix}_${key}.webp`))
    );
    for (let j = 0; j < batch.length; j++) {
      const key = batch[j];
      const path = `images/${key}.png`;
      entries.push({ path, data: results[j] });
      imagePaths[key] = path;
      done++;
    }
    onProgress?.(done, total);
  }

  const rootId = boardIdFor(sceneJson.homePageKey, sceneIdentity);
  const rootPath = boardPaths[rootId] || Object.values(boardPaths)[0];
  const manifest = manifestJson({
    rootPath,
    boardOrder: boards.map((b) => b.id),
    boardPaths,
    imagePaths,
  });
  entries.unshift({ path: "manifest.json", data: new TextEncoder().encode(manifest) });

  return zipStore(entries);
}

export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
