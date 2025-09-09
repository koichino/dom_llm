using '../main.bicep'

//============================================================
// マスター パラメータファイル: (この bicepparam) main.parameters.bicepparam
//============================================================

//============================================================
// デプロイ共通: ロケーション & RG
//============================================================
param location = 'japaneast'              // すべてのリソース配置リージョン
param resourceGroupName = 'rg-domllm-demo2' // 新規 or 既存 RG 名 (reuseExistingRg=false で新規作成)
param reuseExistingRg = false              // true: 既存 RG を再利用 / false: 作成
param prefix = 'demo'                      // タグ等で利用 (将来拡張用)

//============================================================
// Automation Account + Runbook 対象
//============================================================
param automationAccountName = 'demo-auto-accnt-1' // Automation Account 名 (既存衝突回避のため変更)
param runbookStartUrl = 'https://raw.githubusercontent.com/koichino/dom_llm/main/infra/runbooks/runbook-start-vmss.ps1' // 起動 Runbook コンテンツURL (フォルダ移動後)
param runbookStopUrl  = 'https://raw.githubusercontent.com/koichino/dom_llm/main/infra/runbooks/runbook-stop-vmss.ps1'  // 停止 Runbook コンテンツURL (フォルダ移動後)
param runbookContentVersion = '1.0.1'     // Runbook コード更新時にインクリメント (publishContentLink.version)

// スケジュール設定 (平日用)
param startScheduleTime = '08:00'         // 平日開始 (HH:MM) 現地表記
param stopScheduleTime  = '00:00'         // 平日停止 (00:00=翌日00:00)
param timeZone = 'Asia/Tokyo'             // 表示/記録用タイムゾーン (テンプレート内部は変換しない)
param jobScheduleVersion = '1'            // ジョブスケジュール GUID 再生成トリガ (変更で再作成)

// 初回スケジュール開始日 (YYYY-MM-DD) ※任意指定/外部制御可  main.bicep の既定はデプロイ日 (utcNow) → 過去判定はしないシンプル運用
// （任意で開始日を固定したい場合は main.bicep 側の scheduleAnchorDate パラメータを追加指定してください）

//============================================================
// VM Scale Set (Runbook が操作)
//============================================================
param vmssName = 'demo-vmss'              // 対象 VMSS 名

//============================================================
// Network / App Gateway (統合版)
//============================================================
param vnetName = 'vnet-web'                       // VNet 名
param appGatewaySubnetName = 'appGatewaySubnet'   // AppGW 用サブネット
param backendSubnetName = 'backendSubnet'         // VMSS 用サブネット
param backendNsgName = 'nsg-backend'              // Backend subnet NSG
param publicIpName = 'agw-pip'                    // AppGW Public IP
param appGatewayName = 'agw-web'                  // Application Gateway 名
param backendPoolName = 'vmssPool'                // Backend Pool 名
param httpSettingsName = 'appGatewayBackendHttpSettings' // HTTP Settings 名
param probeName = 'probe-http'                    // Probe 名

//============================================================
// VMSS 詳細 (cloud-init で簡易 HTTP)
//============================================================
param adminUsername = 'azureuser'                 // VMSS 管理ユーザ
// SSH 公開鍵必須化: パスワード認証は無効化済み。以下のようにこのファイル末尾などで adminPublicKey を追加してください:
// param adminPublicKey = 'ssh-rsa AAAA... yourkey'
// （下にプレースホルダを追加しています。実際の公開鍵に置き換えてください）
param adminPublicKey = 'ssh-rsa REPLACE_ME_your_actual_public_key'

//============================================================
// API Management (最小構成)
//============================================================
param apimName = 'apim-web'                       // APIM 名
param apimPublisherEmail = 'admin@example.com'    // 発行者メール
param apimPublisherName = 'admin'                 // 発行者名
