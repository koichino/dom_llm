# インフラ (Bicep) + Automation Runbook サンプル (日本語版)

このリポジトリは Azure Automation Account + (将来的に拡張可能な) VM Scale Set 管理向けのモジュール型 Bicep 構成と、VMSS 起動/停止用 PowerShell Runbook、平日スケジュール (月～金) をデプロイするサンプルです。現在は統合された **サブスクリプション スコープ** テンプレート `infra/main.bicep` を使用します。

## 構成概要
- `infra/main.bicep` : サブスクリプションスコープ (RG 作成 + モジュール呼び出し)
- `infra/modules/automationAccount.bicep` : Automation Account + Managed Identity + 役割割り当て
- `infra/modules/runbooksAndSchedules.bicep` : Runbook (Start/Stop) & 平日スケジュール & JobSchedule
- `infra/modules/vmss.bicep` : 将来の VMSS 定義用プレースホルダ
- `infra/parameters/main.parameters.json` : 単一パラメータファイル
- `runbooks/runbook-start-vmss.ps1` / `runbooks/runbook-stop-vmss.ps1` : VMSS 起動/停止 Runbook (週末スキップロジックあり)

## 主なパラメータ (抜粋)
| 名前 | 説明 |
|------|------|
| location | デプロイ先リージョン (例: japaneast) |
| resourceGroupName | 作成/再利用する RG 名 |
| reuseExistingRg | true=既存 RG 再利用 / false=新規作成 |
| automationAccountName | Automation Account 名 (グローバル一意) |
| vmssName | 対象 VMSS 名 (将来拡張用) |
| startScheduleTime | ローカル (Tokyo Standard Time) 開始時刻 (HH:MM) |
| stopScheduleTime | ローカル停止時刻 (HH:MM, 24:00 可) |
| scheduleAnchorDate | 初回開始日 (YYYY-MM-DD, ローカル時間として解釈) |
| runbookContentVersion | Runbook コンテンツ強制更新用バージョン |
| jobScheduleVersion | JobSchedule 再生成用バージョン |
| startJobScheduleSalt / stopJobScheduleSalt | 片方のみ再生成したい場合の追加シード |

## スケジュール仕様
* 平日 (Mon–Fri) のみ実行 (`advancedSchedule.weekDays`).
* `startScheduleTime`, `stopScheduleTime` は `timeZone` (既定: Tokyo Standard Time) のローカル時刻文字列。
* `stopScheduleTime` を `24:00` とすると翌日 00:00 と解釈。
* Automation 側で `startTime` は `YYYY-MM-DDTHH:MM:SS` 形式 + `timeZone` によりローカル変換されます。

## デプロイ手順 (PowerShell / ルートディレクトリ)
```powershell
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>

# （必要ならパラメータファイルを編集）
$deploymentName = "deploy-$(Get-Date -Format yyyyMMddHHmmss)"
az deployment sub create `
	--name $deploymentName `
	--location japaneast `
	--template-file infra/main.bicep `
	--parameters @infra/parameters/main.parameters.json `
	-o table
```

### 出力確認
```powershell
az deployment sub show --name $deploymentName --query properties.outputs
```

### スケジュール / Runbook 確認
```powershell
$params = Get-Content infra/parameters/main.parameters.json | ConvertFrom-Json
$rg  = $params.parameters.resourceGroupName.value
$aa  = $params.parameters.automationAccountName.value
az automation runbook list -g $rg -a $aa -o table
az automation schedule list -g $rg -a $aa -o table
```

## バージョン/再生成の運用ルール
| 目的 | 変更する値 |
|------|-------------|
| Runbook スクリプト内容更新を強制 | `runbookContentVersion` をインクリメント |
| Start/Stop 両 JobSchedule 再生成 | `jobScheduleVersion` をインクリメント |
| Start のみ再生成 | `startJobScheduleSalt` を新しい文字列に変更 |
| Stop のみ再生成 | `stopJobScheduleSalt` を新しい文字列に変更 |
| 初回発火日をずらす | `scheduleAnchorDate` を未来日 (YYYY-MM-DD) へ |

## トラブルシュート
| 症状 | 原因 | 対処 |
|------|------|------|
| Schedule BadRequest (startTime) | 過去日時 / 不正フォーマット | `scheduleAnchorDate` を未来日に / HH:MM 形式確認 |
| jobSchedule Conflict | GUID シード同一 | `jobScheduleVersion` か salt を変更 |
| Runbook がリンク表示されない | jobSchedule 生成失敗 | Conflict 解消後再デプロイ |
| 時刻がずれている | ローカル/JST と UTC の解釈ミス | Local モード (現行) では `timeZone` を正しく維持 |

## セキュリティ / ベストプラクティス
* Managed Identity を利用し資格情報をコードに埋め込まない。
* 最小権限 (Contributor など必要最小ロール) を対象 RG / VMSS に付与。
* Bicep モジュールは小さく分割し API バージョンを固定。
* CI/CD は GitHub Actions + OIDC (`azure/login`) + Key Vault シークレット参照推奨。

## 既存 VMSS への権限付与
`automation/assign-role-to-vmss.ps1` を利用して Automation Account MI に対象 VMSS への Contributor を付与可能:
```powershell
./automation/assign-role-to-vmss.ps1 -ResourceGroupName <RG> -AutomationAccountName <AA> -VmssName <VMSS>
```

## 休日/祝日除外など拡張案
| 要件 | 方針 (例) |
|------|-----------|
| 祝日スキップ | Runbook 冒頭で日本の祝日 API/テーブルを参照し早期 return |
| 複数時間帯 | 追加スケジュールと別 Runbook/パラメータ化 |
| 地域別時差 | `timeZone` パラメータを許可配列拡張 + 必要ならローカル→UTC 変換モード復活 |

## クリーンアップ
```powershell
az group delete --name <resourceGroupName> --yes --no-wait
```

---
質問や追加要望 (祝日対応/本番向け強化など) があれば Issue / PR / 追加依頼をしてください。

