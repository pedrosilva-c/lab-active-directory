<#
.SYNOPSIS
  Coleta evidências SOMENTE LEITURA do controlador de domínio do laboratório.

.DESCRIPTION
  Executar no SERVER-DC, em PowerShell como administrador do domínio.
  Nenhum comando altera configuração: só consultas (Get-*, dcdiag, ipconfig).
  Gera uma pasta evidencias-DC-<data> com um .txt por tópico e um resumo.
  Cada seção roda isolada: se um papel (ex.: DHCP) não estiver instalado,
  a falha é registrada no arquivo e a coleta continua.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Coletar-EvidenciasDC.ps1
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path $PSScriptRoot ("evidencias-DC-" + (Get-Date -Format 'yyyyMMdd-HHmm')))
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$resumo = [System.Collections.Generic.List[string]]::new()

function Save-Evidence {
    param([string]$Nome, [scriptblock]$Bloco)
    $arquivo = Join-Path $Destino ("{0}.txt" -f $Nome)
    try {
        $saida = & $Bloco 2>&1 | Out-String -Width 220
        "# $Nome — coletado em $(Get-Date -Format 's') em $env:COMPUTERNAME`r`n`r`n$saida" |
            Set-Content -Path $arquivo -Encoding UTF8
        $resumo.Add("[OK]    $Nome")
    } catch {
        "# $Nome — FALHOU: $($_.Exception.Message)" | Set-Content -Path $arquivo -Encoding UTF8
        $resumo.Add("[FALHA] $Nome — $($_.Exception.Message)")
    }
}

Save-Evidence '01-sistema'        { Get-ComputerInfo -Property OsName, OsVersion, CsName, CsDomain, CsDomainRole | Format-List }
Save-Evidence '02-papeis'         { Get-WindowsFeature | Where-Object Installed | Select-Object Name, DisplayName | Format-Table -AutoSize }
Save-Evidence '03-rede'           { ipconfig /all }
Save-Evidence '04-dominio'        { Import-Module ActiveDirectory; Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode, PDCEmulator | Format-List }
Save-Evidence '05-floresta'       { Import-Module ActiveDirectory; Get-ADForest | Select-Object Name, ForestMode, SchemaMaster, GlobalCatalogs | Format-List }
Save-Evidence '06-ous'            { Import-Module ActiveDirectory; Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Sort-Object DistinguishedName | Format-Table -AutoSize }
Save-Evidence '07-grupos'         { Import-Module ActiveDirectory; Get-ADGroup -Filter 'GroupCategory -eq "Security" -and GroupScope -ne "DomainLocal"' -SearchBase (Get-ADDomain).DistinguishedName |
                                      Where-Object { $_.DistinguishedName -notmatch 'CN=Users,|CN=Builtin,' } | Select-Object Name, GroupScope | Format-Table -AutoSize }
Save-Evidence '08-usuarios'       { Import-Module ActiveDirectory; Get-ADUser -Filter * -Properties Enabled | Where-Object { $_.DistinguishedName -match 'OU=' } |
                                      Select-Object SamAccountName, Enabled, @{n='OU';e={($_.DistinguishedName -split ',',2)[1]}} | Format-Table -AutoSize }
Save-Evidence '09-computadores'   { Import-Module ActiveDirectory; Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate | Select-Object Name, OperatingSystem, LastLogonDate | Format-Table -AutoSize }
Save-Evidence '10-gpos'           { Import-Module GroupPolicy; Get-GPO -All | Select-Object DisplayName, GpoStatus, CreationTime, ModificationTime | Format-Table -AutoSize }
Save-Evidence '11-gpo-links'      { Import-Module ActiveDirectory; Import-Module GroupPolicy
                                      Get-ADOrganizationalUnit -Filter * | ForEach-Object { $l = (Get-GPInheritance -Target $_.DistinguishedName).GpoLinks
                                      if ($l) { [pscustomobject]@{ OU = $_.Name; GPOs = ($l.DisplayName -join '; ') } } } | Format-Table -AutoSize }
Save-Evidence '12-dns-zonas'      { Get-DnsServerZone | Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone | Format-Table -AutoSize }
Save-Evidence '13-dhcp-escopos'   { Get-DhcpServerv4Scope | Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State | Format-Table -AutoSize }
Save-Evidence '14-dhcp-opcoes'    { Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4OptionValue -ScopeId $_.ScopeId } | Format-Table -AutoSize }
Save-Evidence '15-compartilhamentos' { Get-SmbShare | Where-Object { -not $_.Special } | Select-Object Name, Path, Description | Format-Table -AutoSize }
Save-Evidence '16-dcdiag'         { dcdiag /q }

$resumo | Set-Content -Path (Join-Path $Destino '00-resumo.txt') -Encoding UTF8
$resumo
Write-Host "`nEvidências salvas em: $Destino" -ForegroundColor Cyan
Write-Host "Revise os arquivos antes de publicar (nomes de usuários do laboratório são fictícios?)." -ForegroundColor Yellow
exit 0
