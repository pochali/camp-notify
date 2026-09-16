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
# 除外:
#   施設名に「オートキャンプ」を含むもの
#
# 判定:
#   空白 = 余裕あり → ○
#   △    = 混雑     → △
#   ×    = 空きなし
#   休   = 休み
#
# Discord:
#   1900文字以内に分割して送信
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
# 明日 ～ 来月末
# ------------------------------------------------------------

$today = (Get-Date).Date

$startDate = $today.AddDays(1)

$nextNextMonth = $today.AddMonths(2)

$endDate = (
    Get-Date `
        -Year $nextNextMonth.Year `
        -Month $nextNextMonth.Month `
        -Day 1
).AddDays(-1)


# ------------------------------------------------------------
# 対象日
# 土曜日・日曜日のみ
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


if (-not (Test-Path $logDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $logDirectory `
        -Force | Out-Null
}


# ------------------------------------------------------------
# ログ
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
# 日本語曜日
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
# 10/25(日)
# ------------------------------------------------------------

function Format-TargetDate {

    param(
        [datetime]$Date
    )

    $week = Get-JapaneseDayOfWeek `
        -Date $Date

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

    $text = [System.Web.HttpUtility]::HtmlDecode(
        $text
    )

    return $text.Trim()
}


# ------------------------------------------------------------
# 対象日か判定
# ------------------------------------------------------------

function Test-TargetDate {

    param(
        [datetime]$Date
    )

    if (
        $Date -lt $startDate -or
        $Date -gt $endDate
    ) {

        return $false
    }


    if (
        $Date.DayOfWeek -ne [DayOfWeek]::Saturday -and
        $Date.DayOfWeek -ne [DayOfWeek]::Sunday
    ) {

        return $false
    }


    return $true
}


# ------------------------------------------------------------
# Discord通知
# 1900文字以内で分割
# ------------------------------------------------------------

function Send-DiscordNotification {

    param(
        [string]$Message
    )

    try {

        Write-Log `
            "Discordメッセージ全体文字数: $($Message.Length)"


        $maxLength = 1900

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

                    $messages += `
                        $currentMessage.TrimEnd()
                }


                $currentMessage = $newLine
            }
            else {

                $currentMessage += $newLine
            }
        }


        if (
            -not [string]::IsNullOrWhiteSpace(
                $currentMessage
            )
        ) {

            $messages += `
                $currentMessage.TrimEnd()
        }


        Write-Log `
            "Discord通知分割数: $($messages.Count)"


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
                -Body $bodyBytes |
                Out-Null


            Write-Log `
                "Discord通知送信成功: $messageNumber/$($messages.Count)"


            $messageNumber++
        }

    }
    catch {

        Write-Log `
            "ERROR: Discord通知送信失敗"

        Write-Log `
            $_.Exception.Message
    }
}


# ============================================================
# 1キャンプ場のチェック
# ============================================================

function Check-CampSite {

    param(
        [string]$SiteName,
        [string]$Url
    )


    Write-Log ""

    Write-Log `
        "========================================"

    Write-Log `
        "【$SiteName】チェック開始"

    Write-Log `
        "========================================"


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

        Write-Log `
            "ERROR: $SiteName のページ取得失敗"

        Write-Log `
            $_.Exception.Message

        return @()
    }


    $html = $response.Content


    Write-Log `
        "ページ取得成功 HTMLサイズ=$($html.Length)"


    # --------------------------------------------------------
    # table取得
    # --------------------------------------------------------

    $tables = [regex]::Matches(
        $html,
        '(?is)<table[^>]*>(.*?)</table>'
    )


    $results = @()


    # ========================================================
    # TABLE
    # ========================================================

    foreach ($tableMatch in $tables) {

        $tableHtml = $tableMatch.Value


        # ----------------------------------------------------
        # 空室表以外は無視
        # ----------------------------------------------------

        if (
            $tableHtml -notmatch "宿泊施設タイプ"
        ) {

            continue
        }


        Write-Log `
            "空室テーブル検出"


        # ----------------------------------------------------
        # 行取得
        # ----------------------------------------------------

        $rows = [regex]::Matches(
            $tableHtml,
            '(?is)<tr[^>]*>(.*?)</tr>'
        )


        # ----------------------------------------------------
        # 現在有効な日付ヘッダー
        # ----------------------------------------------------

        $currentDateIndexes = @{}


        # ----------------------------------------------------
        # 現在解析している月
        # ----------------------------------------------------

        $currentMonth = $null
        $currentYear = $null


        # ====================================================
        # ROW
        # ====================================================

        foreach ($rowMatch in $rows) {

            $rowHtml = $rowMatch.Value


            $cells = [regex]::Matches(
                $rowHtml,
                '(?is)<t[dh][^>]*>(.*?)</t[dh]>'
            )


            if ($cells.Count -eq 0) {

                continue
            }


            $rowText = `
                Convert-HtmlToText $rowHtml


            # =================================================
            # 月情報取得
            # =================================================

            $detectedMonth = $null


            if (
                $rowText -match '(\d{1,2})月'
            ) {

                $detectedMonth = `
                    [int]$matches[1]


                $candidateYear = $startDate.Year


                # 年跨ぎ対応
                if (
                    $detectedMonth -lt $startDate.Month
                ) {

                    $candidateYear++
                }


                $currentMonth = $detectedMonth
                $currentYear = $candidateYear


                Write-Log `
                    "月検出: $currentYear/$currentMonth"
            }


            # =================================================
            # この行が日付ヘッダーか判定
            # =================================================

            $numericCellCount = 0


            foreach ($cell in $cells) {

                $value = `
                    Convert-HtmlToText `
                        $cell.Groups[1].Value


                if (
                    $value -match '^\d{1,2}$'
                ) {

                    $numericCellCount++
                }
            }


            # -------------------------------------------------
            # 数字セルが複数ある場合は
            # 日付ヘッダーとみなす
            # -------------------------------------------------

            if ($numericCellCount -ge 2) {


                Write-Log `
                    "日付ヘッダー検出"


                # ------------------------------------------------
                # 新しいヘッダーが出たら
                # 前の日付列情報を破棄
                # ------------------------------------------------

                $currentDateIndexes = @{}


                # ------------------------------------------------
                # 月情報がない場合
                # ------------------------------------------------

                if ($null -eq $currentMonth) {

                    $currentMonth = $startDate.Month
                    $currentYear = $startDate.Year
                }


                $previousDay = $null

                $workingMonth = $currentMonth
                $workingYear = $currentYear


                # =============================================
                # 日付セル
                # =============================================

                for (
                    $i = 0;
                    $i -lt $cells.Count;
                    $i++
                ) {

                    $value = `
                        Convert-HtmlToText `
                            $cells[$i].Groups[1].Value


                    if (
                        $value -notmatch '^\d{1,2}$'
                    ) {

                        continue
                    }


                    $day = [int]$value


                    # =========================================
                    # 月跨ぎ判定
                    #
                    # 例:
                    # 29
                    # 30
                    # 1 ← 翌月
                    # 2
                    # =========================================

                    if (
                        $null -ne $previousDay -and
                        $day -lt $previousDay
                    ) {

                        $workingMonth++


                        if (
                            $workingMonth -gt 12
                        ) {

                            $workingMonth = 1
                            $workingYear++
                        }


                        Write-Log `
                            "月跨ぎ検出 → $workingYear/$workingMonth"
                    }


                    $previousDay = $day


                    # =========================================
                    # DateTime生成
                    # =========================================

                    try {

                        $date = Get-Date `
                            -Year $workingYear `
                            -Month $workingMonth `
                            -Day $day `
                            -Hour 0 `
                            -Minute 0 `
                            -Second 0

                    }
                    catch {

                        continue
                    }


                    # =========================================
                    # 土日のみ
                    # =========================================

                    if (
                        -not (
                            Test-TargetDate `
                                -Date $date
                        )
                    ) {

                        continue
                    }


                    # =========================================
                    # 列番号 → 正確な日付
                    # =========================================

                    $currentDateIndexes[$i] = `
                        $date


                    $formattedDate = `
                        Format-TargetDate `
                            -Date $date


                    Write-Log `
                        "日付列検出: $formattedDate → 列 $i"
                }


                # 日付ヘッダー自身は施設として扱わない
                continue
            }


            # =================================================
            # 日付ヘッダーがまだ無い場合
            # =================================================

            if (
                $currentDateIndexes.Count -eq 0
            ) {

                continue
            }


            # =================================================
            # 施設名
            # =================================================

            $facility = `
                Convert-HtmlToText `
                    $cells[0].Groups[1].Value


            if (
                [string]::IsNullOrWhiteSpace(
                    $facility
                )
            ) {

                continue
            }


            # =================================================
            # ヘッダー・施設除外
            #
            # 「オートキャンプ」を含む施設は対象外
            # =================================================

            if (
                $facility -match "宿泊施設タイプ" -or
                $facility -match "空白=" -or
                $facility -match "オートキャンプ" -or
                $facility -match '^\d+$'
            ) {

                if (
                    $facility -match "オートキャンプ"
                ) {

                    Write-Log `
                        "除外施設: $facility"
                }

                continue
            }


            # =================================================
            # 各対象日
            # =================================================

            foreach (
                $index in $currentDateIndexes.Keys
            ) {

                if (
                    $index -ge $cells.Count
                ) {

                    continue
                }


                $targetDate = `
                    $currentDateIndexes[$index]


                # ------------------------------------------------
                # ステータス
                # ------------------------------------------------

                $cellHtml = `
                    $cells[$index].Groups[1].Value


                $status = `
                    Convert-HtmlToText `
                        $cellHtml


                # ------------------------------------------------
                # × = 空きなし
                # ------------------------------------------------

                if (
                    $status -eq "×"
                ) {

                    continue
                }


                # ------------------------------------------------
                # 休 = 休み
                # ------------------------------------------------

                if (
                    $status -eq "休"
                ) {

                    continue
                }


                # ------------------------------------------------
                # - = 対象外
                # ------------------------------------------------

                if (
                    $status -eq "-"
                ) {

                    continue
                }


                # ------------------------------------------------
                # 空白 = ○
                # ------------------------------------------------

                if (
                    [string]::IsNullOrWhiteSpace(
                        $status
                    )
                ) {

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
                # 結果
                # ------------------------------------------------

                $result = `
                    [PSCustomObject]@{

                        Site = `
                            $SiteName

                        Date = `
                            $targetDate

                        Facility = `
                            $facility

                        Status = `
                            $status

                        Url = `
                            $Url
                    }


                $results += `
                    $result
            }
        }
    }


    return $results
}


# ============================================================
# メイン
# ============================================================

try {

    Write-Log ""

    Write-Log `
        "########################################"

    Write-Log `
        "CAMP and CABINS 空室チェック開始"


    Write-Log `
        "対象期間: $($startDate.ToString('yyyy/MM/dd')) ～ $($endDate.ToString('yyyy/MM/dd'))"


    Write-Log `
        "対象曜日: 土曜日・日曜日"


    Write-Log `
        "対象日数: $($targetDates.Count)"


    Write-Log `
        "除外条件: 施設名に「オートキャンプ」を含む"


    Write-Log `
        "########################################"


    # --------------------------------------------------------
    # 対象日ログ
    # --------------------------------------------------------

    foreach ($targetDate in $targetDates) {

        $formattedDate = `
            Format-TargetDate `
                -Date $targetDate


        Write-Log `
            "対象日: $formattedDate"
    }


    # --------------------------------------------------------
    # TLS1.2
    # --------------------------------------------------------

    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12


    # --------------------------------------------------------
    # HTML Decode
    # --------------------------------------------------------

    Add-Type `
        -AssemblyName System.Web


    # --------------------------------------------------------
    # 全結果
    # --------------------------------------------------------

    $allResults = @()


    # --------------------------------------------------------
    # キャンプ場
    # --------------------------------------------------------

    foreach ($site in $sites) {

        $results = `
            Check-CampSite `
                -SiteName $site.Name `
                -Url $site.Url


        if (
            $null -ne $results
        ) {

            $allResults += `
                $results
        }
    }


    # ========================================================
    # 重複除去
    # ========================================================

    $allResults = @(
        $allResults |
            Sort-Object `
                Site,
                Date,
                Facility,
                Status `
                -Unique
    )


    # ========================================================
    # 結果
    # ========================================================

    Write-Log ""

    Write-Log `
        "########################################"

    Write-Log `
        "チェック結果"

    Write-Log `
        "########################################"


    if (
        $allResults.Count -gt 0
    ) {


        # ----------------------------------------------------
        # 日付 → 場所 → 施設
        # ----------------------------------------------------

        $allResults = `
            $allResults |
                Sort-Object `
                    Date,
                    Site,
                    Facility


        Write-Log ""

        Write-Log `
            "★ 空き候補あり！"

        Write-Log ""


        # ----------------------------------------------------
        # ログ
        # ----------------------------------------------------

        foreach ($result in $allResults) {

            $formattedDate = `
                Format-TargetDate `
                    -Date $result.Date


            $message = `
                "★【$($result.Site)】 " +
                "$formattedDate " +
                "$($result.Facility) " +
                "[$($result.Status)]"


            Write-Log `
                $message
        }


        # ====================================================
        # Discord
        # ====================================================

        $discordMessage = @"

🏕️ CAMP and CABINS 空きあり！

"@


        # ----------------------------------------------------
        # キャンプ場ごと
        # ----------------------------------------------------

        foreach ($site in $sites) {

            $siteResults = @(
                $allResults |
                    Where-Object {
                        $_.Site -eq $site.Name
                    }
            )


            if (
                $siteResults.Count -eq 0
            ) {

                continue
            }


            $discordMessage += @"

【$($site.Name)】

"@


            # ------------------------------------------------
            # 日付順
            # ------------------------------------------------

            $siteResults = `
                $siteResults |
                    Sort-Object `
                        Date,
                        Facility


            foreach ($result in $siteResults) {

                $formattedDate = `
                    Format-TargetDate `
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


        # ----------------------------------------------------
        # チェック日時
        # ----------------------------------------------------

        $discordMessage += @"

チェック日時:
$(Get-Date -Format "yyyy/MM/dd HH:mm:ss")

"@


        # ----------------------------------------------------
        # Discord送信
        # ----------------------------------------------------

        Send-DiscordNotification `
            -Message $discordMessage

    }
    else {

        Write-Log ""


        Write-Log `
            "$($startDate.ToString('yyyy/MM/dd')) ～ $($endDate.ToString('yyyy/MM/dd')) の土日に空き候補なし"
    }


    Write-Log ""

    Write-Log `
        "チェック終了"

    Write-Log `
        "########################################"

    Write-Log ""

}
catch {

    Write-Log ""

    Write-Log `
        "ERROR: 処理中にエラーが発生しました"

    Write-Log `
        $_.Exception.Message

    exit 1
}
