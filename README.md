# Camelot

macOS 26向けのキーボード操作ユーティリティです。Optionキーを短くタップすると、前面ウィンドウの操作可能なコントロールに一時キーを表示し、そのキーで対象を選びます。操作にはmacOSのAccessibility情報を使い、アプリやコントロールが公開する情報により動作範囲が変わります。macOSのAccessibilityやInput Monitoringの許可が必要です。

配布ページは準備中で、現在ダウンロードできる公開版はありません。GitHubリポジトリはprivateのため、一般向けReleaseもまだありません。

## 開発

必要環境: macOS 26、Xcode 26以降（Swift 6.2）。

```sh
Scripts/verify.sh
Scripts/build-app.sh
```

## 配布

Developer ID署名、Apple notarization、GitHub Releaseの準備手順は[docs/apple-distribution.md](docs/apple-distribution.md)を参照してください。署名済み配布物はまだ公開していません。

LPのローカルプレビューは次で開けます。

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs/site
```

PlaywrightとChromiumが既にある環境では、ブラウザー操作の確認もできます。

```sh
node Scripts/test-site.cjs
```
