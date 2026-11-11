<#
.SYNOPSIS
  Coleta evidências SOMENTE LEITURA de uma estação do laboratório (ex.: CLIENTE02).

.DESCRIPTION
  Executar na estação, logado com um usuário do domínio (não o administrador local),
  para comprovar ingresso no domínio, resolução de nomes, DHCP e aplicação de GPO.
  Nenhum comando altera configuração.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Coletar-EvidenciasCliente.ps1
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path $PSScriptRoot ("evidencias-{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')))
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

Save-Evidence '01-identidade'   { whoami; whoami /groups /fo table }
Save-Evidence '02-dominio'      { Get-CimInstance Win32_ComputerSystem | Select-Object Name, Domain, PartOfDomain, DomainRole | Format-List }
Save-Evidence '03-canal-seguro' { "Canal seguro com o domínio: " + (Test-ComputerSecureChannel) }
Save-Evidence '04-rede'         { ipconfig /all }
Save-Evidence '05-dns'          { $d = (Get-CimInstance Win32_ComputerSystem).Domain; nslookup $d; Resolve-DnsName -Type SRV "_ldap._tcp.dc._msdcs.$d" | Format-Table -AutoSize }
Save-Evidence '06-gpresult'     { gpresult /r }
Save-Evidence '07-unidades'     { Get-PSDrive -PSProvider FileSystem | Where-Object DisplayRoot | Select-Object Name, DisplayRoot | Format-Table -AutoSize }

$resumo | Set-Content -Path (Join-Path $Destino '00-resumo.txt') -Encoding UTF8
$resumo
Write-Host "`nEvidências salvas em: $Destino" -ForegroundColor Cyan
exit 0
