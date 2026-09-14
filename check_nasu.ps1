# ============================================================
# CAMP and CABINS 空室チェック
#
# 対象:
#   ・那須高原
#   ・山中湖
#
# 対象日:
#   2026/9/19
#   2026/9/20
#   2026/9/21
#   2026/9/22
#
# 判定:
#   空白 = 余裕あり → ○
#   △    = 混雑     → △
#   ×    = 空きなし
#   休   = 休み
#
# 空きがあった場合:
#   Discord Webhookへ通知
# ============================================================


# ------------------------------------------------------------
# Discord設定
# ★ここだけ自分のWebhook URLに変更
# ------------------------------------------------------------

$discordWebhookUrl = $env:DISCORD_WEBHOOK_URL


# ------------------------------------------------------------
# キャンプ場設定
# ------------------------------------------------------------

$sites = @(
    @{
        Name = "那須高原"
        Url  = "https://reser.camp-cabins.com/cc_reserve/sv_open?login_mode=%27%27"
    },
    @{
        Name = "山中湖"
        Url  = "https://reser.yagai-kikaku.com/cc_reserve/sv_open?login_mode=%27%27"
    }
)


# ------------------------------------------------------------
# 対象日
# ------------------------------------------------------------

$targetDays = @(19, 20, 21, 22)


# ------------------------------------------------------------
# ログ設定
# ------------------------------------------------------------

$logDirectory = "C:\camp"
$logFile = "$logDirectory\camp_check.log"


# ------------------------------------------------------------
# ログフォルダ作成
# ------------------------------------------------------------

if (-not (Test-Path $logDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $logDirectory `
        -Force | Out-Null
}


# ------------------------------------------------------------
# ログ出力
# ------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $line = "[$time] $Message"

    Write-Host $line

    Add-Content `
        -Path $logFile `
        -Value $line `
        -Encoding UTF8
}


# ------------------------------------------------------------
# HTML → テキスト
# ------------------------------------------------------------

function Convert-HtmlToText {

    param(
        [string]$Html
    )

    $text = $Html -replace '<[^>]+>', ''

    $text = [System.Web.HttpUtility]::HtmlDecode($text)

    return $text.Trim()
}


# ------------------------------------------------------------
# Discord通知
# ------------------------------------------------------------

function Send-DiscordNotification {

    param(
        [string]$Message
    )

    try {

        $body = @{
            content = $Message
        } | ConvertTo-Json


        # 日本語文字化け対策
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)


        Invoke-RestMethod `
            -Uri $discordWebhookUrl `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $bodyBytes | Out-Null


        Write-Log "Discord通知送信成功"

    }
    catch {

        Write-Log "ERROR: Discord通知送信失敗"

        Write-Log $_.Exception.Message
    }
}


# ------------------------------------------------------------
# 1キャンプ場の空室チェック
# ------------------------------------------------------------

function Check-CampSite {

    param(
        [string]$SiteName,
        [string]$Url
    )


    Write-Log ""
    Write-Log "========================================"
    Write-Log "【$SiteName】チェック開始"
    Write-Log "========================================"


    # --------------------------------------------------------
    # ページ取得
    # --------------------------------------------------------

    try {

        $response = Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -Headers @{
                "User-Agent" = "Mozilla/5.0"
            }

    }
    catch {

        Write-Log "ERROR: $SiteName のページ取得失敗"

        Write-Log $_.Exception.Message

        return @()
    }


    $html = $response.Content


    Write-Log "ページ取得成功 HTMLサイズ=$($html.Length)"


    # --------------------------------------------------------
    # table取得
    # --------------------------------------------------------

    $tables = [regex]::Matches(
        $html,
        '(?is)<table[^>]*>(.*?)</table>'
    )


    $results = @()


    foreach ($tableMatch in $tables) {

        $tableHtml = $tableMatch.Value


        # ----------------------------------------------------
        # 空室表か確認
        # ----------------------------------------------------

        if ($tableHtml -notmatch "宿泊施設タイプ") {

            continue
        }


        # ----------------------------------------------------
        # 行取得
        # ----------------------------------------------------

        $rows = [regex]::Matches(
            $tableHtml,
            '(?is)<tr[^>]*>(.*?)</tr>'
        )


        # ----------------------------------------------------
        # 日付列
        # ----------------------------------------------------

        $dayIndexes = @{}


        foreach ($rowMatch in $rows) {

            $rowHtml = $rowMatch.Value


            $cells = [regex]::Matches(
                $rowHtml,
                '(?is)<t[dh][^>]*>(.*?)</t[dh]>'
            )


            if ($cells.Count -eq 0) {

                continue
            }


            for ($i = 0; $i -lt $cells.Count; $i++) {

                $value = Convert-HtmlToText `
                    $cells[$i].Groups[1].Value


                if ($value -match '^\d{1,2}$') {

                    $day = [int]$value


                    if ($targetDays -contains $day) {

                        if (-not $dayIndexes.ContainsKey($day)) {

                            $dayIndexes[$day] = $i

                            Write-Log `
                                "日付列検出: 9/$day → 列 $i"
                        }
                    }
                }
            }


            if ($dayIndexes.Count -eq $targetDays.Count) {

                break
            }
        }


        # ----------------------------------------------------
        # 日付列が見つからない
        # ----------------------------------------------------

        if ($dayIndexes.Count -eq 0) {

            Write-Log "対象の日付列を検出できませんでした"

            continue
        }


        # ----------------------------------------------------
        # 各施設行
        # ----------------------------------------------------

        foreach ($rowMatch in $rows) {

            $rowHtml = $rowMatch.Value


            $cells = [regex]::Matches(
                $rowHtml,
                '(?is)<t[dh][^>]*>(.*?)</t[dh]>'
            )


            if ($cells.Count -eq 0) {

                continue
            }


            # ------------------------------------------------
            # 施設名
            # ------------------------------------------------

            $facility = Convert-HtmlToText `
                $cells[0].Groups[1].Value


            if ([string]::IsNullOrWhiteSpace($facility)) {

                continue
            }


            # ------------------------------------------------
            # ヘッダー等除外
            # ------------------------------------------------

            if (
                $facility -match "宿泊施設タイプ" -or
                $facility -match "空白=" -or
                $facility -match '^\d+$'
            ) {

                continue
            }


            # ------------------------------------------------
            # 対象日
            # ------------------------------------------------

            foreach ($day in $targetDays) {

                if (-not $dayIndexes.ContainsKey($day)) {

                    continue
                }


                $index = $dayIndexes[$day]


                if ($index -ge $cells.Count) {

                    continue
                }


                # ------------------------------------------------
                # ステータス取得
                # ------------------------------------------------

                $cellHtml = $cells[$index].Groups[1].Value

                $status = Convert-HtmlToText $cellHtml


                # ------------------------------------------------
                # × = 空きなし
                # ------------------------------------------------

                if ($status -eq "×") {

                    continue
                }


                # ------------------------------------------------
                # 休 = 休み
                # ------------------------------------------------

                if ($status -eq "休") {

                    continue
                }


                # ------------------------------------------------
                # - = 対象外
                # ------------------------------------------------

                if ($status -eq "-") {

                    continue
                }


                # ------------------------------------------------
                # 空白 = 余裕あり
                # ------------------------------------------------

                if ([string]::IsNullOrWhiteSpace($status)) {

                    $status = "○"
                }


                # ------------------------------------------------
                # ○ / 〇 / △ のみ通知対象
                # ------------------------------------------------

                if (
                    $status -ne "○" -and
                    $status -ne "〇" -and
                    $status -ne "△"
                ) {

                    continue
                }


                # ------------------------------------------------
                # 結果保存
                # ------------------------------------------------

                $result = [PSCustomObject]@{

                    Site     = $SiteName

                    Day      = $day

                    Facility = $facility

                    Status   = $status

                    Url      = $Url
                }


                $results += $result
            }
        }
    }


    return $results
}


# ============================================================
# メイン処理
# ============================================================

try {

    Write-Log ""
    Write-Log "########################################"
    Write-Log "CAMP and CABINS 空室チェック開始"
    Write-Log "対象日: 9/19, 9/20, 9/21, 9/22"
    Write-Log "########################################"


    # --------------------------------------------------------
    # TLS1.2
    # --------------------------------------------------------

    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12


    # --------------------------------------------------------
    # HTML Decode
    # --------------------------------------------------------

    Add-Type -AssemblyName System.Web


    # --------------------------------------------------------
    # 全結果
    # --------------------------------------------------------

    $allResults = @()


    # --------------------------------------------------------
    # 那須高原 + 山中湖
    # --------------------------------------------------------

    foreach ($site in $sites) {

        $results = Check-CampSite `
            -SiteName $site.Name `
            -Url $site.Url


        if ($null -ne $results) {

            $allResults += $results
        }
    }


    # ========================================================
    # 結果
    # ========================================================

    Write-Log ""
    Write-Log "########################################"
    Write-Log "チェック結果"
    Write-Log "########################################"


    if ($allResults.Count -gt 0) {


        # ----------------------------------------------------
        # ソート
        # ----------------------------------------------------

        $allResults = $allResults |
            Sort-Object Day, Site, Facility


        # ----------------------------------------------------
        # ログ
        # ----------------------------------------------------

        Write-Log ""
        Write-Log "★ 空き候補あり！"
        Write-Log ""


        foreach ($result in $allResults) {

            $message = `
                "★【$($result.Site)】 " +
                "9/$($result.Day) " +
                "$($result.Facility) " +
                "[$($result.Status)]"


            Write-Log $message
        }


        # ====================================================
        # Discord通知メッセージ作成
        # ====================================================

        $discordMessage = @"

🏕️ CAMP and CABINS 空きあり！

"@


        # ----------------------------------------------------
        # 場所ごとにまとめる
        # ----------------------------------------------------

        foreach ($site in $sites) {

            $siteResults = $allResults |
                Where-Object {
                    $_.Site -eq $site.Name
                }


            if ($siteResults.Count -gt 0) {

                $discordMessage += @"

【$($site.Name)】

"@


                foreach ($result in $siteResults) {

                    $discordMessage += `
                        "9/$($result.Day) " +
                        "$($result.Facility) " +
                        "[$($result.Status)]`n"
                }


                $discordMessage += @"

予約ページ
$($site.Url)

"@
            }
        }


        $discordMessage += @"

チェック日時:
$(Get-Date -Format "yyyy/MM/dd HH:mm:ss")

"@


        # ====================================================
        # Discord送信
        # ====================================================

        Send-DiscordNotification `
            -Message $discordMessage


    }
    else {

        Write-Log ""
        Write-Log "9/19～9/22 空き候補なし"

        # 空きなしの場合はDiscord通知しない
    }


    Write-Log ""
    Write-Log "チェック終了"
    Write-Log "########################################"
    Write-Log ""

}
catch {

    Write-Log ""
    Write-Log "ERROR: 処理中にエラーが発生しました"

    Write-Log $_.Exception.Message

    exit 1
}