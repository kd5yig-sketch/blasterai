// Tile grid rendering and navigation. Ported behavior from
// claudeBlast/Views/TileGridView.swift and docs/porting.md §4, simplified for
// the web: a responsive CSS grid replaces the iOS pagination math
// (GridLayoutCalculator) — tiles wrap and the page scrolls instead of
// paging, which is a deliberate web-idiomatic simplification.

import { colorForWordClass, colorForPartOfSpeech, labelColorOn, CHROME, NAVIGATION } from "./color.js";

const HOME_PAGE_KEY = "home";

export class TileGrid {
  constructor({ root, scene, vocabByKey, vocabularyClasses, imageSetPrefix, settings, onTap, onNavigate }) {
    this.root = root;
    this.scene = scene; // Map<pageKey, placements[]>
    this.vocabByKey = vocabByKey;
    this.vocabularyClasses = vocabularyClasses;
    this.imageSetPrefix = imageSetPrefix;
    this.settings = settings;
    this.onTap = onTap; // (tile) => void — a word tile was tapped
    this.onNavigate = onNavigate; // (pageKey) => void
    this.currentPage = this.scene.get(HOME_PAGE_KEY) ? HOME_PAGE_KEY : [...this.scene.keys()][0];
    this.breadcrumb = [];
  }

  navigateTo(pageKey) {
    if (!this.scene.has(pageKey)) return;
    if (pageKey !== this.currentPage) this.breadcrumb.push(this.currentPage);
    this.currentPage = pageKey;
    this.render();
    if (this.onNavigate) this.onNavigate(pageKey);
  }

  navigateHome() {
    this.breadcrumb = [];
    this.currentPage = HOME_PAGE_KEY;
    this.render();
  }

  artSrc(artKey) {
    return `assets/tiles/${this.imageSetPrefix}_${artKey}.webp`;
  }

  render() {
    const placements = this.scene.get(this.currentPage) || [];
    const cells = [];

    // Home is cell 0 of every non-home page — invariant position, styled as
    // chrome, not vocabulary (docs/porting.md §4).
    if (this.currentPage !== HOME_PAGE_KEY) {
      cells.push({ key: HOME_PAGE_KEY, chrome: true, homeLink: true, label: "home" });
    }

    for (const p of placements) {
      const vocab = this.vocabByKey.get(p.key);
      if (!vocab) continue;
      cells.push({ key: p.key, placement: p, vocab });
    }

    this.root.innerHTML = "";
    this.root.setAttribute("role", "grid");
    for (const cell of cells) {
      this.root.appendChild(this._renderCell(cell));
    }
  }

  _renderCell(cell) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "tile";

    let color, artKey, label;

    if (cell.homeLink) {
      color = CHROME;
      artKey = "home";
      label = "home";
    } else if (cell.placement.link) {
      color = NAVIGATION;
      artKey = cell.vocab.artKey;
      label = cell.vocab.label;
    } else {
      color = colorForWordClass(cell.vocab.wordClass, this.vocabularyClasses);
      artKey = cell.vocab.artKey;
      label = cell.vocab.label;
    }

    const img = document.createElement("img");
    img.src = this.artSrc(artKey);
    img.alt = label;
    img.draggable = false;
    img.onerror = () => {
      img.style.display = "none";
    };
    button.appendChild(img);

    const labelBand = document.createElement("span");
    labelBand.className = "tile-label";
    labelBand.style.background = color;
    labelBand.style.color = labelColorOn(color);
    labelBand.textContent = label;
    button.appendChild(labelBand);

    button.setAttribute("aria-label", label);
    button.addEventListener("click", () => this._handleTap(cell));
    return button;
  }

  _handleTap(cell) {
    if (cell.homeLink) {
      this.navigateHome();
      return;
    }
    const { placement, vocab } = cell;
    if (placement.link) {
      if (placement.audible) this.onTap(vocab);
      this.navigateTo(placement.to);
      return;
    }
    this.onTap(vocab);
  }
}
