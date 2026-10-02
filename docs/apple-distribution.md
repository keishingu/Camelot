# CamelotのmacOS直接配布

CamelotはmacOS 26向けです。直接配布ではDeveloper ID ApplicationでHardened Runtime署名したUniversal DMGをAppleへnotarizeし、ticketをstapleしてからGitHub Releaseへ公開します。現在の`keishingu/Camelot`はprivateで、ReleaseとApple配布用GitHub Variables/Secretsは未登録です。`publish: true`のworkflowはpublic repositoryかを確認し、privateのままなら公開前に停止します。LPは公開前の案内に留め、ダウンロード可能とは表示しません。配布先が決まるまでは、リポジトリの公開設定を変更しません。

## 成果物

| 項目 | 値 |
|---|---|
| App | `Camelot.app` |
| Bundle ID | `com.keishingu.camelot` |
| DMG | `Camelot-macos-universal.dmg` |
| CPU | `arm64`、`x86_64` |
| 最低OS | macOS 26 |
| 署名 | Developer ID Application、Hardened Runtime、secure timestamp |
| DMG内の導線 | `Camelot.app` と `/Applications` ショートカット |

## GitHub Actionsの設定

`Settings → Secrets and variables → Actions`に登録します。

Variables:

| Name | 内容 |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID |

Secrets:

| Name | 内容 |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | 秘密鍵を含むDeveloper ID Application `.p12`のbase64 |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | `.p12`の書き出しパスワード |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | notary用`.p8`のbase64 |

証明書・API key・パスワードはリポジトリやログへ出さないでください。`.p12`と`.p8`の発行・権限管理はApple Developerアカウントの管理者が行います。

## 手動リリース

`.github/workflows/release-macos.yml`は手動実行のみです。実行時にXcode 26.0.1を選び、XcodeとSwift 6.2を検証します。GitHubのmacOS 26 runner imageにはXcode 26.0.1が含まれます（[runner imageのソフトウェア一覧](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md#xcode)）。

`publish`は初期値OFFです。OFFならrepositoryへのアクセス権がある人向けに、7日間保持のActions artifactだけを作成します。ONにできるのは`main`だけで、成功時はpublic repositoryに限り`v<version>-<run number>`のGitHub ReleaseへDMGとSHA-256ファイルを添付します。workflowを初めて動かす前に、public配布先と上記Apple設定、署名証明書の有効性、Appleのnotary API key権限を確認してください。

## LPの手動公開

`.github/workflows/deploy-pages.yml`は手動実行のみで、`main`かつpublic repositoryであることと`docs/site/index.html`の存在を検証してからPages artifactを作成します。最初にGitHub repositoryの`Settings → Pages → Build and deployment → Source`を`GitHub Actions`に設定してください。workflowは設定を変更しません。現在のrepositoryはprivateなので、このworkflowは公開前の段階で停止します。publicにするrepositoryか配布専用repositoryかが決まるまで実行しません。

ローカルでは次で静的LPを確認できます。

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs/site
```

## ローカル実行

開発用アプリは既存スクリプトで作れます。

```sh
Scripts/build-app.sh
```

署名済みDMG作成にはmacOS 26/Xcode 26.0.1、Developer ID Application identityが必要です。次のコマンドはビルドと署名を実行し、既存の`build/release`を検知した場合は上書きせず終了します。

```sh
BUILD_NUMBER=1 \
MARKETING_VERSION=0.1.0 \
SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
Scripts/build-direct-release.sh
```

Apple notarizationは、`.p8`を一時ファイルとして用意し、次の環境変数を設定して実行します。notarizationが`Accepted`の場合のみstaple、Gatekeeper/署名/DMG検証、SHA-256作成へ進みます。

```sh
NOTARY_KEY_PATH=/private/path/AuthKey_KEYID.p8 \
APP_STORE_CONNECT_KEY_ID=KEYID \
APP_STORE_CONNECT_ISSUER_ID=ISSUERID \
Scripts/notarize-release.sh
```

配布前にはDMGを実機で開き、Applicationsへのコピー、初回起動、アプリの実用途に必要な権限と動作を確認します。これらの実機確認と公開ページの確認が済むまでは、`publish`をONにしないでください。

## リリース状態

- 署名・notarization・checksumを行うスクリプトと手動workflow: 実装済み
- Apple証明書、GitHub Variables/Secrets: 未登録（設定名の有無のみ確認。値は参照していません）
- notary受理済み配布物、GitHub Release: なし
- 実機インストール確認、一般公開LP: 本作業では未確認
- 無料配布、購入、ライセンスキー、自動更新: 仕様未決定のため対象外
