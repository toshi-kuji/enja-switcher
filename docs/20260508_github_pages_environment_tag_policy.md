# GitHub Pages の environment 保護とタグ起動 deploy の仕組み

**日付**: 2026-05-08
**きっかけ**: v1.3.0 リリース時に GitHub Actions の deploy job が失敗（`Tag "v1.3.0" is not allowed to deploy to github-pages due to environment protection rules.`）

このドキュメントは、その調査と修正を通して学んだことのまとめ。

---

## 1. 起きたこと（症状）

GitHub Release `v1.3.0` を公開した直後、`.github/workflows/deploy.yml` が `release: published` イベントで起動。

- `build` job → ✅ 成功
- `deploy` job → ❌ 2 秒で failure

エラーメッセージ：

> Tag "v1.3.0" is not allowed to deploy to github-pages due to environment protection rules.
> The deployment was rejected or didn't satisfy other protection rules.

最初は「急に壊れた」ように見えたが、実は **v1.1.0 以降ずっと失敗していた**ことが履歴調査で判明（後述）。

---

## 2. 根本原因

GitHub Actions の **environment 保護ルール**で、`github-pages` environment への deploy を許可する ref が **`main` ブランチのみ**に絞られていた。

`release: published` イベントで起動した workflow run は `github.ref` が **タグ**（`v1.3.0`）になる。タグは許可リストに入っていなかったため、deploy job が environment ゲートで弾かれた。

---

## 3. 概念整理：2 つのレイヤー

これが今回の最大の学び。**workflow / build 側** と **environment / 受け入れ側** は別レイヤー。

| レイヤー | 場所 | 何を決めるか | 誰が触れるか |
|---|---|---|---|
| **workflow / build 側** | `.github/workflows/deploy.yml`（リポジトリ内） | いつ起動するか・何をビルドするか・どの environment にデプロイ要求を出すか | git push できる人なら誰でも |
| **environment / 受け入れ側** | GitHub サーバ上の repo settings | デプロイ要求を **受け入れるか拒否するか**（ref のホワイトリスト、reviewer 必須、wait timer 等） | repo admin のみ。UI または API でしか変更不可 |

`deploy.yml` の以下の行は「**この environment に向けて投げる**」と宣言しているだけ：

```yaml
deploy:
  environment:
    name: github-pages
```

その先で受け入れられるかは environment 側の設定次第。今回は受け入れ側で tag が許可リストに無かったので拒否されていた。

### なぜリポジトリのファイルに含まれないのか

GitHub の意図的な設計判断で、**「コードを書ける人」と「本番にデプロイできる人」を分離する**ため。`.yml` で自由に変更できると、悪意あるコミットでルールを緩められてしまうので、environment 保護は repo settings 側に分離されている。

その結果：

- `git clone` で持っていけない
- `.yml` を編集しても変えられない
- リポジトリを fork しても引き継がれない
- IaC 化したいなら Terraform の `github_repository_environment` リソース等で別途管理

---

## 4. 許可リストの実体（deployment branch/tag policy）

### 場所

3 つの見方がある。

**① GitHub Web UI**

```
https://github.com/<owner>/<repo>/settings/environments
```

→ `github-pages` をクリック → 下の方の **"Deployment branches and tags"** セクション。"Add deployment branch or tag rule" ボタンから追加・削除できる。

**② GitHub API（CLI）**

```bash
gh api repos/<owner>/<repo>/environments/github-pages/deployment-branch-policies
```

返り値の例：

```json
{
  "total_count": 2,
  "branch_policies": [
    {"id": 46366742, "name": "main",   "type": "branch"},
    {"id": 48861123, "name": "v*.*.*", "type": "tag"}
  ]
}
```

JSON のキー名は `branch_policies` だが branch と tag の両方が入る（API 命名が古いだけ）。

**③ リポジトリのファイル → 存在しない**（前述の通り）

### policy の種類（GitHub UI 上の選択肢）

| 設定 | 意味 |
|---|---|
| **All branches and tags** | 制限なし |
| **Protected branches only** | branch protection rules が掛かったブランチのみ |
| **Selected branches and tags**（custom） | 自分でパターンを列挙する |

このリポジトリは custom 設定。

### branch policy と tag policy の違い

custom 設定で追加するパターンには **type** がある：

- `type: branch` — branch 名にマッチ（例：`main`、`release/*`）
- `type: tag` — tag 名にマッチ（例：`v*.*.*`、`v1.*`）

ブランチ名とタグ名は名前空間が別。`main` を branch として追加しても tag は通らないし、`v*.*.*` を tag として追加しても branch は通らない。**両方を網羅したいなら 2 つ登録する必要がある**。

### パターン構文

`fnmatch` 風のグロブ：

- `*` — 任意の文字列（`/` も含む）
- `?` — 任意の 1 文字
- 完全一致したい時は `*` を使わない（`main` は `main` だけ通す）

`v*.*.*` は `v1.0.0`、`v1.3.0`、`v10.20.30` などにマッチ。`v1.0.0-beta1` のような prerelease タグも通したいなら `v*` の方が安全。

---

## 5. tag policy の正しい意味

「タグの作成や push が CI を起動する」ための設定では **ない**。

| ステップ | どこで起きる | tag policy の関係 |
|---|---|---|
| ① タグ作成 / Release 公開 | GitHub | 無関係 |
| ② workflow 起動（`on: release: published`） | GitHub Actions | **無関係**（workflow 自体は常に起動） |
| ③ build job 実行 | runner | 無関係 |
| ④ deploy job 実行（`environment: github-pages`） | runner + environment 保護 | **ここで tag policy がチェックされる** |

つまり tag policy は「**この environment への deploy 要求を許可するか**」だけを決めるゲート。workflow の起動・build 実行までは policy 無しでも動く。実際、過去 v1.1.0/v1.2.0 でも build job は成功していて、deploy job だけが弾かれていた。

run のトリガーは `.github/workflows/deploy.yml` の `on:` 節（`release: published` と `push to main`）で決まる。

---

## 6. なぜ v1.3.0 で初めて顕在化したか（履歴）

| Release | 日付 | release event の deploy | 同時間帯の他経由の deploy |
|---|---|---|---|
| v1.0.0 | 2026-04-05 | （environment 作成前で起動せず） | — |
| v1.1.0 | 2026-04-06 | ❌ 失敗 | ✅ 直後の手動 workflow_dispatch + `fix: include deploy.yml...` push が肩代わり |
| v1.2.0 | 2026-04-11 | ❌ 失敗 | ✅ 直後の `feat: fix scroll reversal...` push（website を変更）が肩代わり |
| v1.3.0 | 2026-05-07 | ❌ 失敗 | **無し**（commit に `[skip ci]` が付いていたため） |

**ポイント**：

- v1.1.0/v1.2.0 でも release-trigger deploy は同じ理由で失敗していた
- ただし **直後に website を触る別 push（または手動 workflow_dispatch）が走り、そっちが成功して肩代わり**していた
- そのため「リリースで deploy が動いた」と記憶されていたが、実際に成功していたのは別経由の deploy
- v1.3.0 で `[skip ci]` 運用を導入（リリース前 push が古いバージョンを取得する別問題への対策）したことで、肩代わり経路が消滅
- 結果、release イベントが唯一の deploy 経路になり、長年隠れていた失敗が表に出た

CLAUDE.md の運用ルール変更が、別の隠れたバグを露呈させた典型例。

---

## 7. 修正手順（今回実施）

### 1) tag policy を追加

```bash
gh api -X POST repos/toshi-kuji/enja-switcher/environments/github-pages/deployment-branch-policies \
  -f name='v*.*.*' -f type='tag'
```

### 2) 失敗した workflow run を再実行

```bash
gh run rerun 25511775073 --failed
```

### 3) 進行確認

```bash
gh run view 25511775073 --json status,conclusion,jobs
```

→ `deploy: success` になり、website が v1.3.0 で再デプロイされた。

---

## 8. GitHub Pages 固有の罠 vs 他 deploy 先

environment 保護は **GitHub Actions 共通の機能**で、deploy 先を問わず同じ仕組みが使える。違いは「自動作成されるか」「保護がデフォルトで強いられるか」。

| 構成例 | environment 名 | 自動作成？ | デフォルト保護 |
|---|---|---|---|
| GitHub Pages | `github-pages` | ✅ 自動 | **最初から branch policy が `main` のみ**（今回の罠） |
| AWS / GCP / Vercel / Fly.io 等 | `production`、`staging` を自分で命名 | ❌ 手動作成 | 自分で設定するまで保護なし |
| Cloudflare Pages（GitHub 連携） | Cloudflare 側で管理 | （Actions 経由なら自分で命名） | 同上 |

### GitHub Pages 固有の部分

- `github-pages` という environment は **GitHub によって自動作成**される（最初に Pages 用 workflow を流した瞬間に勝手にできる）
- 作成時に **deployment branch policy が `main` のみで初期化される**（GitHub のデフォルト）
- `actions/deploy-pages@v4` が内部で `environment: github-pages` を要求するため回避不可
- これが今回ハマった「気づかないうちに main-only の制限が掛かっていた」の正体

### 一般化した教訓

任意の environment で `release: published` 等の **タグ起動 workflow から deploy する場合**、最初に environment の policy にタグパターン（`v*.*.*` 等）を入れておくのがチェックリスト項目になる。これは GitHub Pages に限らず、production environment で reviewer 必須にしている本番デプロイなどでも同じく踏みやすい罠。

---

## 9. このセッションでの学び（要約）

1. **GitHub Actions には 2 つのレイヤーがある** — workflow（リポジトリ内・誰でも編集可）と environment 保護（GitHub サーバ上・admin のみ）。後者はファイルに残らず、`.yml` からは変更できない
2. **environment 保護の許可リストは「deployment branch/tag policy」と呼ばれ、branch 用と tag 用が別レコード**。両方欲しいなら 2 つ登録
3. **`release: published` で起動した workflow の `github.ref` はタグ**。だから tag policy が無いと environment で弾かれる
4. **`github-pages` environment は GitHub が自動作成し、最初から `main` のみの branch policy が入っている**。これが GitHub Pages 固有の罠
5. **build job が成功しても deploy job が environment で弾かれることがある**。今回のように 2 秒で failure になったら environment 保護を疑う
6. **隠れた失敗は別の運用変更で表面化することがある**（今回は `[skip ci]` 運用の導入が、肩代わりしていた別 deploy を消し、本来の失敗を露呈させた）
7. **「workflow が走るか」と「environment にデプロイできるか」は別の話**。tag policy は後者だけを開ける
8. environment 保護は **本番にデプロイできる人を絞る** ためのセキュリティ機能。だからこそ意図的にリポジトリの外に置かれている
