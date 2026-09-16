# ============================================================
# CAMP and CABINS 空室チェック
#
# 対象:
#   ・那須高原
#   ・山中湖
#
# 対象期間:
#   実行日の翌日 ～ 来月末
#
# 対象曜日:
#   土曜日・日曜日のみ
#
# 判定:
#   空白 = 余裕あり → ○
#   △    = 混雑     → △
#   ×    = 空きなし
#   休   = 休み
#
# 空きがあった場合:
#   Discord Webhookへ通知
#
# Discord:
#   1メッセージ1900文字以内に分割して送信
# ============================================================


# ------------------------------------------------------------
# Discord設定
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
# 対象期間
# 実行日の翌日 ～ 来月末
# ------------------------------------------------------------

$today = (Get-Date).Date

$startDate = $today.AddDays(1)

# 翌々月1日の前日 = 来月末
$endDate = (Get-Date `
    -Year $today.AddMonths(2).Year `
    -Month $today.AddMonths(2).Month `
    -Day 1).AddDays(-1)


# ------------------------------------------------------------
# 対象日一覧作成
#
# 明日 ～ 来月末のうち
# 土曜日・日曜日のみ対象
# ------------------------------------------------------------

$targetDates = @()

$currentDate = $startDate

while ($currentDate -le $endDate) {

    if (
        $currentDate.DayOfWeek -eq [DayOfWeek]::Saturday -or
        $currentDate.DayOfWeek -eq [DayOfWeek]::Sunday
    ) {

        $targetDates += $currentDate
    }

    $currentDate = $currentDate.AddDays(1)
}


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
# 日本語曜日取得
# ------------------------------------------------------------

function Get-JapaneseDayOfWeek {

    param(
        [datetime]$Date
    )

    $weekdays = @(
        "日",
        "月",
        "火",
        "水",
        "木",
        "金",
        "土"
    )

    return $weekdays[[int]$Date.DayOfWeek]
}


# ------------------------------------------------------------
# 日付表示
#
# 例:
#   9/19(土)
# ------------------------------------------------------------

function Format-TargetDate {

    param(
        [datetime]$Date
    )

    $week = Get-JapaneseDayOfWeek -Date $Date

    return "$($Date.Month)/$($Date.Day)($week)"
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
#
# Discordのcontentは2000文字まで。
# 安全のため1900文字以内に分割して送信する。
# ------------------------------------------------------------

function Send-DiscordNotification {

    param(
        [string]$Message
    )

    try {

        Write-Log "Discordメッセージ全体文字数: $($Message.Length)"

        $maxLength = 1900

        # 改行単位に分割
        $lines = $Message -split "`r?`n"

        $messages = @()
        $currentMessage = ""

        foreach ($line in $lines) {

            $newLine = $line + "`n"

            if (
                ($currentMessage.Length + $newLine.Length) `
                    -gt $maxLength
            ) {

                if (
                    -not [string]::IsNullOrWhiteSpace(
                        $currentMessage
                    )
                ) {

                    $messages += $currentMessage.TrimEnd()
                }

                $currentMessage = $newLine
            }
            else {

                $currentMessage += $newLine
            }
        }


        # ----------------------------------------------------
        # 最後に残ったメッセージ
        # ----------------------------------------------------

        if (
            -not [string]::IsNullOrWhiteSpace(
                $currentMessage
            )
        ) {

            $messages += $currentMessage.TrimEnd()
        }


        Write-Log "Discord通知分割数: $($messages.Count)"


        # ----------------------------------------------------
        # 分割したメッセージを順番に送信
        # ----------------------------------------------------

        $messageNumber = 1


        foreach ($messagePart in $messages) {

            Write-Log `
                "Discord通知送信: $messageNumber/$($messages.Count) 文字数=$($messagePart.Length)"


            $body = @{
                content = $messagePart
            } | ConvertTo-Json


            $bodyBytes = `
                [System.Text.Encoding]::UTF8.GetBytes(
                    $body
                )


            Invoke-RestMethod `
                -Uri $discordWebhookUrl `
                -Method Post `
                -ContentType "application/json; charset=utf-8" `
                -Body $bodyBytes | Out-Null


            Write-Log `
                "Discord通知送信成功: $messageNumber/$($messages.Count)"


            $messageNumber++
        }

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
        #
        # Key   = 列番号
        # Value = DateTime
        # ----------------------------------------------------

        $dateIndexes = @{}


        # ----------------------------------------------------
        # HTMLの日付ヘッダーから対象日を検出
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
            # 行に含まれる月を取得
            # ------------------------------------------------

            $rowText = Convert-HtmlToText $rowHtml

            $detectedMonth = $null


            if ($rowText -match '(\d{1,2})月') {

                $detectedMonth = [int]$matches[1]
            }


            # ------------------------------------------------
            # 各セル確認
            # ------------------------------------------------

            for ($i = 0; $i -lt $cells.Count; $i++) {

                $value = Convert-HtmlToText `
                    $cells[$i].Groups[1].Value


                # --------------------------------------------
                # 日だけのセル
                # --------------------------------------------

                if ($value -match '^\d{1,2}$') {

                    $day = [int]$value


                    # ----------------------------------------
                    # 土日の対象日から候補取得
                    # ----------------------------------------

                    $candidates = @(
                        $targetDates |
                            Where-Object {
                                $_.Day -eq $day
                            }
                    )


                    if ($candidates.Count -eq 0) {

                        continue
                    }


                    # ----------------------------------------
                    # 月が取得できている場合
                    # ----------------------------------------

                    if ($null -ne $detectedMonth) {

                        $targetDate = `
                            $candidates |
                                Where-Object {
                                    $_.Month -eq $detectedMonth
                                } |
                                Select-Object -First 1

                    }
                    else {

                        $targetDate = `
                            $candidates |
                                Sort-Object |
                                Select-Object -First 1
                    }


                    if ($null -eq $targetDate) {

                        continue
                    }


                    # ----------------------------------------
                    # 列番号をキーに保存
                    # ----------------------------------------

                    if (-not $dateIndexes.ContainsKey($i)) {

                        $dateIndexes[$i] = $targetDate


                        $formattedDate = `
                            Format-TargetDate `
                                -Date $targetDate


                        Write-Log `
                            "日付列検出: $formattedDate → 列 $i"
                    }
                }
            }
        }


        # ----------------------------------------------------
        # 日付列が見つからない
        # ----------------------------------------------------

        if ($dateIndexes.Count -eq 0) {

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

            foreach ($index in $dateIndexes.Keys) {

                if ($index -ge $cells.Count) {

                    continue
                }


                $targetDate = $dateIndexes[$index]


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

                    Date     = $targetDate

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

    Write-Log `
        "対象期間: $($startDate.ToString('yyyy/MM/dd')) ～ $($endDate.ToString('yyyy/MM/dd'))"

    Write-Log "対象曜日: 土曜日・日曜日"

    Write-Log "対象日数: $($targetDates.Count)"

    Write-Log "########################################"


    # --------------------------------------------------------
    # 対象日をログ出力
    # --------------------------------------------------------

    foreach ($targetDate in $targetDates) {

        $formattedDate = Format-TargetDate `
            -Date $targetDate

        Write-Log "対象日: $formattedDate"
    }


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
        # 日付 → 場所 → 施設
        # ----------------------------------------------------

        $allResults = $allResults |
            Sort-Object Date, Site, Facility


        # ----------------------------------------------------
        # ログ
        # ----------------------------------------------------

        Write-Log ""
        Write-Log "★ 空き候補あり！"
        Write-Log ""


        foreach ($result in $allResults) {

            $formattedDate = Format-TargetDate `
                -Date $result.Date


            $message = `
                "★【$($result.Site)】 " +
                "$formattedDate " +
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

            $siteResults = @(
                $allResults |
                    Where-Object {
                        $_.Site -eq $site.Name
                    }
            )


            if ($siteResults.Count -gt 0) {

                $discordMessage += @"

【$($site.Name)】

"@


                foreach ($result in $siteResults) {

                    $formattedDate = Format-TargetDate `
                        -Date $result.Date


                    $discordMessage += `
                        "$formattedDate " +
                        "$($result.Facility) " +
                        "[$($result.Status)]`n"
                }


                $discordMessage += @"

予約ページ
$($site.Url)

"@
            }
        }


        # ----------------------------------------------------
        # チェック日時
        # ----------------------------------------------------

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

        Write-Log `
            "$($startDate.ToString('yyyy/MM/dd')) ～ $($endDate.ToString('yyyy/MM/dd')) の土日に空き候補なし"
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
