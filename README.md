# ドメイン内 LLM 実験環境 向け Azure インフラ (Bicep) / Automation サンプル

現在の構成は単一のサブスクリプション スコープ Bicep (`infra/main.bicep`) に以下をまとめています:

- Resource Group の作成 (または再利用)
- ネットワーク & Application Gateway (Standard_v2 L7 ロードバランサ)
- VM Scale Set (Linux / cloud-init による簡易 HTTP サービス)
- Automation Account (Managed Identity) + 起動/停止 Runbook + 平日スケジュール
- API Management (最小プレースホルダ)
- 役割割り当て (Automation MI → VMSS へ Contributor)

パスワード認証は無効化し、VMSS は SSH 公開鍵必須運用です。

## 事前インストール / 必要ツール
ローカル (デプロイ実行端末) 側で以下が利用可能であること:

| ツール / モジュール | 用途 | 確認コマンド (PowerShell) |
|---------------------|------|---------------------------|
| Azure CLI (最新推奨) | Bicep 組込み/サブスクリプション デプロイ | `az version` |
| Bicep CLI (az に同梱) | Lint/What-if (任意) | `bicep --version` |
| PowerShell 7+ (任意) | 補助スクリプト実行 | `pwsh -v` |
| OpenSSH クライアント | SSH 接続 | `ssh -V` |

Automation Runbook 実行環境 (Azure 側) で必要になるモジュール: `Az.Accounts`, `Az.Compute`. 既定の Cloud / 最新 Runtime では自動解決されますが、古い Runtime を使う場合は Gallery からインポートしてください。

## 最小前提 (サブスクリプション / 権限)
| 前提 | 内容 |
|------|------|
| サブスクリプション権限 | `Owner` か少なくとも RG 作成 + ロール割り当てが可能な権限 |
| リージョン | 例: `japaneast` (App Gateway / Automation / APIM 利用可能) |
| ネーム重複回避 | `automationAccountName`, `apimName` はグローバル一意性要件に注意 |
| SSH 公開鍵 | `adminPublicKey` に設定 (パスワード無し) |

## クイック デプロイ手順 (最小)

1. ログイン / サブスクリプション選択
```powershell
az login
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```
2. SSH 公開鍵 (未作成なら)
```powershell
ssh-keygen -t ed25519 -C vmss-admin -f .\id_vmss
```
3. パラメータファイル修正 (`infra/parameters/main.parameters.bicepparam` の `adminPublicKey` を `id_vmss.pub` 内容に置換)
4. What-if (任意)
```powershell
$region = 'japaneast'   # リージョン (東日本). 変更する場合は bicepparam の location も合わせる
$name   = "domllm-$(Get-Date -Format yyyyMMddHHmmss)"  # デプロイメント名 (一意性確保のため時刻付与)
az deployment sub what-if -n "${name}-whatif" -l $region --parameters infra/parameters/main.parameters.bicepparam
```
5. デプロイ
```powershell
$region = 'japaneast'   # リージョン (東日本). 変更する場合は bicepparam の location も合わせる
$name   = "domllm-$(Get-Date -Format yyyyMMddHHmmss)"  # デプロイメント名 (一意性確保のため時刻付与)
az deployment sub create -n $name -l $region --parameters infra/parameters/main.parameters.bicepparam -o table
```
6. 出力確認
```powershell
az deployment sub show -n $name --query properties.outputs
```
7. VMSS へ SSH (初回インスタンス起動後)
```powershell
# パブリック IP は AppGW 用。VMSS へは内部経路 (Bastion 等) を検討。デモでは AppGW 経由 HTTP のみ想定。
```

> APIM を頻繁に作り直す場合はソフトデリート衝突に注意 (後述)。

## ディレクトリ概要
| パス | 説明 |
|------|------|
| `infra/main.bicep` | サブスクリプション デプロイ統合テンプレート |
| `infra/parameters/main.parameters.bicepparam` | 主要パラメータ定義 (一括指定) |
| `infra/modules/network.bicep` | VNet / Subnets / NSG / Public IP / App Gateway 子リソース |
| `infra/modules/vmss.bicep` | VMSS (Trusted Launch, SSH のみ, cloud-init) |
| `infra/modules/automationAccount.bicep` | Automation Account + MI |
| `infra/modules/runbooksAndSchedules.bicep` | Start / Stop Runbook + 平日スケジュール + JobSchedule |
| `infra/modules/roleAssignments.bicep` | Automation MI → VMSS へのロール付与 |
| `infra/modules/apim.bicep` | APIM プレースホルダ (将来拡張用) |
| `infra/runbooks/runbook-start-vmss.ps1` | VMSS 起動 Runbook (週末スキップ含む) |
| `infra/runbooks/runbook-stop-vmss.ps1`  | VMSS 停止 Runbook (週末スキップ含む) |
| `infra/cloudinit/cloud-init.yaml` | VMSS インスタンス初期化 (簡易 Python HTTP) |
| `.gitignore` | `build/` など生成物除外 |

## 主なリソース関係
Application Gateway のバックエンド プール ← VMSS NIC IP
Automation Runbook (Start/Stop) → VMSS の容量制御 (スケジュール トリガ)

## 代表的パラメータ (詳細は bicepparam 参照)
| パラメータ | 用途 | 例 |
|------------|------|----|
| location | リージョン | japaneast |
| resourceGroupName | RG 名 | rg-domllm-demo2 |
| reuseExistingRg | 既存 RG 再利用フラグ | false |
| automationAccountName | Automation Account | demo-auto-accnt2 |
| vmssName | VMSS 名 | demo-vmss |
| adminUsername | VM 管理ユーザ | azureuser |
| adminPublicKey | SSH 公開鍵 (必須) | ssh-rsa / ed25519 キー |
| startScheduleTime | 平日開始 (ローカル) | 08:00 |
| stopScheduleTime | 平日停止 (24:00=翌日00:00) | 24:00 |
| timeZone | (旧) スケジュールタイムゾーン -> 現在は内部固定 UTC+TZ 変換 | (内部固定) |
| scheduleAnchorDate | 初回基準日 | 2025-09-09 |
| runbookContentVersion | Runbook 強制更新 | 1.0.1 |
| jobScheduleVersion | JobSchedule 再作成トリガ | 2 |

## スケジュール仕様
平日 (Mon–Fri) のみ動作。`startScheduleTime` / `stopScheduleTime` は `timeZone` 基準。`24:00` 指定は翌日 00:00 と解釈。Runbook 側に週末スキップロジックを実装。

## デプロイ (詳細)
上のクイック手順と同じ変数 `$region`, `$name` を再利用してください。

### 追加例: What-if 差分のみ JSON で取得
```powershell
az deployment sub what-if -n "${name}-whatif" -l $region --parameters infra/parameters/main.parameters.bicepparam -o json > whatif.json
```

### 追加例: location を一時上書き (実験)
```powershell
$region = 'japaneast'
az deployment sub create -n $name -l $region --parameters infra/parameters/main.parameters.bicepparam -o table
```

### 再実行時の注意
同一 `$name` を再利用すると以前のデプロイ履歴と区別しづらいので、常にタイムスタンプ付きで再生成推奨。

## SSH 公開鍵例 (作成)
```bash
ssh-keygen -t ed25519 -C "vmss-admin" -f id_vmss
# id_vmss.pub の内容を adminPublicKey に貼り付け
```

## バージョン管理 (再生成トリガ)
| 対象 | インクリメントで何が起こるか |
|------|------------------------------|
| runbookContentVersion | Runbook 本体 (PublishContentLink) 更新強制 |
| jobScheduleVersion | Start / Stop JobSchedule GUID 再生成 |
| scheduleAnchorDate | 初回 startTime の基準日を変更 |

## セキュリティ要点
- VMSS は SSH 公開鍵のみ (PasswordLogin 無効)
- Automation MI に必要最小ロール (VMSS Contributor) のみ付与
- Trusted Launch (Secure Boot + vTPM) 有効化
- 生成物 (`build/`) は Git 管理外

## 運用コマンド例
```powershell
# Runbook / スケジュール一覧
az automation runbook list -g <rg> -a <automationAccount> -o table
az automation schedule list -g <rg> -a <automationAccount> -o table

# VMSS インスタンス数確認
az vmss show -g <rg> -n <vmssName> --query sku.capacity
```

## トラブルシュート (抜粋)
| 事象 | 原因例 | 対処 |
|------|--------|------|
| Schedule 作成失敗 | 過去日時指定 | scheduleAnchorDate を未来日へ |
| Runbook 未更新 | version 未変更 | runbookContentVersion を +1 |
| JobSchedule Conflict | GUID 再生成されない | jobScheduleVersion を +1 |
| SSH 接続不可 | 公開鍵誤り / セキュリティグループ | adminPublicKey 再確認 + NSG ルール調整 |

## APIM の Soft Delete / 再デプロイ注意点
API Management (APIM) は削除 (Delete) 後すぐには名前が解放されず、ソフトデリート状態 (保護期間) になります。この間に同じ `apimName` で再作成 (Bicep 再デプロイ) を試みると、以下のようなエラー/失敗が発生します:

> Name is not available / cannot create because a soft-deleted service exists

### 典型的な状況
1. 既存 APIM を `az apim delete` あるいはポータルで削除。
2. 即座に `infra/main.bicep` を再デプロイ (APIM モジュールは作成を試みる)。
3. 名前衝突 (soft delete 保持中) により失敗。

### 対処パターン
| シナリオ | 推奨アクション |
|----------|----------------|
| 同じ名前で完全に作り直したい | ソフトデリートを purge してから再デプロイ |
| APIM はしばらく不要 (他リソースだけ再デプロイ) | 一時的に `main.bicep` の APIM モジュール部分をコメントアウト / 削除 |
| 削除後すぐ復旧したい (内容を残したい) | (現状テンプレートはバックアップ復元非対応) → purge せず保持し、新規構成は検討 |

### ソフトデリート中の APIM 一覧表示
```powershell
az apim deletedservice list --location japaneast -o table
```

### 永久削除 (Purge) して名前を再利用可能にする
⚠️ Purge は取り消し不能。完全にリソースと構成が失われます。
```powershell
az apim deletedservice purge --name <apimName> --location japaneast
```

### 再デプロイ前チェック (例)
```powershell
$apimName = 'apim-web'
az apim deletedservice list --location japaneast --query "[?name=='$apimName']" -o table
```
出力に該当があれば purge するか、待機 (保持期間終了後に自動的に解放) してください。

### よくある失敗パターンと解決
| 症状 | 原因 | 対策 |
|------|------|------|
| APIM 作成で Name not available | ソフトデリート残骸 | purge 実行→再デプロイ |
| purge コマンドで NotFound | 既に保持期間終了 / 名前解放済 | そのまま再デプロイ可 |
| 再デプロイで別のプロパティ差分エラー | 既存生存 APIM が設定不一致 | 既存を手で調整 or 一旦削除→purge→再作成 |

### テンプレート側で将来的に検討可能な拡張
| 追加案 | 内容 |
|--------|------|
| `deployApim` / `reuseExistingApim` パラメータ | 条件付きモジュール化で再デプロイ柔軟性向上 |
| バックアップ & 復元統合 | `az apim backup/restore` を CI に組み込み |
| SKU 変更ガード | 破壊的 SKU 変更の事前チェック ロジック |

> 現状テンプレートは APIM を無条件作成するため、ソフトデリート直後は purge しない限り失敗します。頻繁に構成を壊して試すフェーズでは、APIM モジュールを一時的にコメントアウトする運用が簡易です。


## 拡張アイデア
| 要件 | 方向性 |
|------|--------|
| HTTPS 化 | AppGW へ証明書 (Key Vault / PFX) + HTTPS Listener 追加 |
| VMSS Autoscale | `capacity` 固定→Autoscale ルール (CPU / Schedule) 導入 |
| ログ収集 | Log Analytics + Diagnostic Settings 追加 |
| Secrets 管理 | Runbook の外部参照を Key Vault 化 |
| 祝日スキップ | Runbook 内 API / テーブル参照で条件分岐 |

## クリーンアップ
```powershell
az group delete -n <resourceGroupName> --yes --no-wait
```

---
追加要望や機能拡張 (Autoscale / HTTPS / Key Vault 連携 など) は Issue / PR で提案してください。

