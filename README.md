# ドメイン内 LLM 実験環境 向け Azure インフラ (Bicep) / Automation サンプル

現在の構成は単一のサブスクリプション スコープ Bicep (`infra/main.bicep`) に以下をまとめています:

- Resource Group の作成 (または再利用)
- ネットワーク & Application Gateway (Standard_v2 L7 ロードバランサ)
- VM Scale Set (Linux / cloud-init による簡易 HTTP サービス)
- Automation Account (Managed Identity) + 起動/停止 Runbook + 平日スケジュール
- API Management (最小プレースホルダ)
- 役割割り当て (Automation MI → VMSS へ Contributor)

パスワード認証は無効化し、VMSS は SSH 公開鍵必須運用です。

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
| timeZone | スケジュールタイムゾーン | Asia/Tokyo |
| scheduleAnchorDate | 初回基準日 | 2025-09-09 |
| runbookContentVersion | Runbook 強制更新 | 1.0.1 |
| jobScheduleVersion | JobSchedule 再作成トリガ | 2 |

## スケジュール仕様
平日 (Mon–Fri) のみ動作。`startScheduleTime` / `stopScheduleTime` は `timeZone` 基準。`24:00` 指定は翌日 00:00 と解釈。Runbook 側に週末スキップロジックを実装。

## デプロイ
最小前提: Azure CLI ログイン済み / 対象サブスクリプション選択済み。

### What-if
```powershell
az deployment sub what-if -n domllm-whatif -l japaneast --parameters infra/parameters/main.parameters.bicepparam
```

### 実デプロイ
```powershell
$name = "domllm-$(Get-Date -Format yyyyMMddHHmmss)"
az deployment sub create -n $name -l japaneast --parameters infra/parameters/main.parameters.bicepparam -o table
```

### 出力参照
```powershell
az deployment sub show -n $name --query properties.outputs
```

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

