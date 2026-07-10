# ============================================================
# audit_windows.ps1
# Script d'audit de securite Windows — equivalent Lynis
# PatchGuard v2.0
# ============================================================

param(
    [string]$LogPath = "C:\PatchGuard\audit-windows.log"
)

# Creer le dossier si necessaire
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = @()

Write-Host "=== AUDIT DE SECURITE WINDOWS ===" -ForegroundColor Cyan
Write-Host "Date : $date" -ForegroundColor Gray

# 1. Mises a jour disponibles
Write-Host "`n[1] Verification des mises a jour..." -ForegroundColor Yellow
$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot 2>$null
$updateCount = if ($updates) { ($updates | Measure-Object).Count } else { 0 }
$report += "Mises a jour disponibles : $updateCount"
Write-Host "    Mises a jour disponibles : $updateCount" -ForegroundColor $(if ($updateCount -gt 0) { "Red" } else { "Green" })

# 2. Windows Defender
Write-Host "`n[2] Verification Windows Defender..." -ForegroundColor Yellow
$defender = Get-MpComputerStatus
$defenderEnabled = $defender.AntivirusEnabled
$defenderUpdated = $defender.AntivirusSignatureLastUpdated
$report += "Windows Defender actif : $defenderEnabled"
$report += "Signatures mises a jour : $defenderUpdated"
Write-Host "    Defender actif : $defenderEnabled" -ForegroundColor $(if ($defenderEnabled) { "Green" } else { "Red" })

# 3. Pare-feu
Write-Host "`n[3] Verification pare-feu..." -ForegroundColor Yellow
$firewall = Get-NetFirewallProfile
$firewallEnabled = ($firewall | Where-Object { $_.Enabled -eq $true }).Count
$report += "Profils pare-feu actifs : $firewallEnabled/3"
Write-Host "    Profils pare-feu actifs : $firewallEnabled/3" -ForegroundColor $(if ($firewallEnabled -eq 3) { "Green" } else { "Red" })

# 4. Comptes administrateurs
Write-Host "`n[4] Verification comptes admin..." -ForegroundColor Yellow
$admins = Get-LocalGroupMember -Group "Administrators" | Measure-Object
$report += "Comptes administrateurs : $($admins.Count)"
Write-Host "    Comptes administrateurs : $($admins.Count)" -ForegroundColor $(if ($admins.Count -gt 3) { "Red" } else { "Green" })

# 5. Services critiques
Write-Host "`n[5] Verification services..." -ForegroundColor Yellow
$criticalServices = @("wuauserv", "MpsSvc", "WinDefend")
foreach ($svc in $criticalServices) {
    $status = (Get-Service -Name $svc -ErrorAction SilentlyContinue).Status
    $report += "Service $svc : $status"
    Write-Host "    $svc : $status" -ForegroundColor $(if ($status -eq "Running") { "Green" } else { "Red" })
}

# 6. Resume et score
$score = 100
if ($updateCount -gt 0) { $score -= ($updateCount * 5) }
if (-not $defenderEnabled) { $score -= 30 }
if ($firewallEnabled -lt 3) { $score -= 20 }
if ($admins.Count -gt 3) { $score -= 10 }
$score = [Math]::Max(0, $score)

Write-Host "`n=== SCORE DE SECURITE : $score/100 ===" -ForegroundColor $(if ($score -ge 70) { "Green" } elseif ($score -ge 50) { "Yellow" } else { "Red" })

# Sauvegarder le rapport
$reportContent = @"
[$date] RAPPORT AUDIT WINDOWS — $(hostname)
$($report -join "`n")
SCORE DE SECURITE : $score/100
"@
Add-Content -Path $LogPath -Value $reportContent

Write-Host "`nRapport sauvegarde : $LogPath" -ForegroundColor Gray
