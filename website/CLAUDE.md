# EnJaSwitcher Website

## Overview
EnJaSwitcher のランディングページ。Astro + GitHub Pages で静的サイトとして公開。

## Technical Constraints
- Astro（静的出力 `output: 'static'`）
- Vanilla CSS のみ（React / Tailwind 不使用）
- JS フレームワーク依存なし（Astro コンポーネントのみ）
- Node.js パッケージは最小限に

## Site Configuration
- site: `https://toshi-kuji.github.io`
- base: `/enja-switcher`
- Hosting: GitHub Pages（GitHub Actions でデプロイ）

## i18n
- 日本語（`/`）がデフォルト、英語（`/en/`）
- テキストは `src/i18n/ja.json` / `en.json` で管理
- ページ側で JSON を import して表示

## Content Source
- ピッチワード（ヘッドライン、3つの特徴）: `TODO/02.web-distribution_20260405.md` Phase 2
- 法的表示（ライセンス、免責事項）: 同 Phase 3
- ページ構成: 同 Phase 4
- LICENSE 全文: `/LICENSE`（リポジトリルート）
- README 免責事項: `/README.md` 末尾

## Pages
- `/` (`index.astro`) — 日本語ランディングページ
- `/license/` (`license.astro`) — MIT License 全文
- `/disclaimer/` (`disclaimer.astro`) — 免責事項
- `/en/` (`en/index.astro`) — English landing page
- `/en/license/` (`en/license.astro`) — MIT License
- `/en/disclaimer/` (`en/disclaimer.astro`) — Disclaimer

## Design Direction
- シンプルで読みやすい
- メニューバー常駐アプリの紹介なので、派手さは不要
- モバイル対応（レスポンシブ）必須
