# setup_lab.ps1
# Script de Automação para Criação das VMs do Laboratório de VPN no VirtualBox
# Execute este script no PowerShell como Administrador.

$ErrorActionPreference = "Stop"

# 1. Definir caminhos e arquivos
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $VBoxManage)) {
    Write-Error "VirtualBox não foi encontrado em '$VBoxManage'. Certifique-se de que o VirtualBox está instalado."
}

$Workspace = $PSScriptRoot
$IsoDir = Join-Path $Workspace "iso"
$VmsDir = Join-Path $Workspace "vms"

# Criar diretórios se não existirem
if (-not (Test-Path $IsoDir)) { New-Item -ItemType Directory -Path $IsoDir | Out-Null }
if (-not (Test-Path $VmsDir)) { New-Item -ItemType Directory -Path $VmsDir | Out-Null }

$PfSenseIsoGz = Join-Path $IsoDir "pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
$PfSenseIso = Join-Path $IsoDir "pfSense-CE-2.7.2-RELEASE-amd64.iso"
$AlpineIso = Join-Path $IsoDir "alpine-virt-3.19.1-x86_64.iso"

# 2. Download dos ISOs se não existirem
Write-Host "=== 1. Verificando e Baixando as Imagens ISO ===" -ForegroundColor Green

if (-not (Test-Path $PfSenseIso) -and -not (Test-Path $PfSenseIsoGz)) {
    Write-Host "Baixando o pfSense ISO (GZ compressed)..." -ForegroundColor Cyan
    $PfSenseUrl = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
    Invoke-WebRequest -Uri $PfSenseUrl -OutFile $PfSenseIsoGz -UserAgent "Mozilla/5.0"
} else {
    Write-Host "pfSense ISO já existe." -ForegroundColor Gray
}

if (-not (Test-Path $PfSenseIso) -and (Test-Path $PfSenseIsoGz)) {
    Write-Host "Descompactando o pfSense ISO usando GzipStream nativo..." -ForegroundColor Cyan
    try {
        $inputGz = [System.IO.File]::OpenRead($PfSenseIsoGz)
        $outputIso = [System.IO.File]::Create($PfSenseIso)
        $gzipStream = New-Object System.IO.Compression.GZipStream($inputGz, [System.IO.Compression.CompressionMode]::Decompress)
        $gzipStream.CopyTo($outputIso)
        $gzipStream.Close()
        $inputGz.Close()
        $outputIso.Close()
        Write-Host "Descompactação concluída!" -ForegroundColor Green
        Remove-Item $PfSenseIsoGz -Force
    } catch {
        Write-Error "Falha ao descompactar: $_"
    }
}

if (-not (Test-Path $AlpineIso)) {
    Write-Host "Baixando o Alpine Linux Virt ISO (Target da LAN)..." -ForegroundColor Cyan
    $AlpineUrl = "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.1-x86_64.iso"
    Invoke-WebRequest -Uri $AlpineUrl -OutFile $AlpineIso -UserAgent "Mozilla/5.0"
} else {
    Write-Host "Alpine Linux ISO já existe." -ForegroundColor Gray
}

Write-Host "ISOs prontas!" -ForegroundColor Green

# 3. Criação da VM pfSense-VPN
Write-Host "`n=== 2. Provisionando a VM pfSense-VPN ===" -ForegroundColor Green
$PfSenseVmName = "pfSense-VPN"

# Verificar se a VM já existe
$VmList = & $VBoxManage list vms
if ($VmList -match $PfSenseVmName) {
    Write-Host "A VM '$PfSenseVmName' já existe no VirtualBox. Pulando criação." -ForegroundColor Yellow
} else {
    Write-Host "Criando a VM '$PfSenseVmName'..." -ForegroundColor Cyan
    
    # Criar VM e registrar no workspace
    & $VBoxManage createvm --name $PfSenseVmName --ostype "FreeBSD_64" --register --basefolder $VmsDir | Out-Null
    
    # Configurar CPU, RAM, Vídeo e Placa de Rede
    & $VBoxManage modifyvm $PfSenseVmName --memory 1024 --cpus 1 --vram 16 | Out-Null
    
    # Configurar Adaptadores de Rede:
    # Adaptador 1: WAN -> Host-Only (VirtualBox Host-Only Ethernet Adapter)
    & $VBoxManage modifyvm $PfSenseVmName --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter" | Out-Null
    # Adaptador 2: LAN -> Rede Interna (intnet)
    & $VBoxManage modifyvm $PfSenseVmName --nic2 intnet --intnet2 "intnet" | Out-Null
    
    # Criar disco virtual de 8GB
    $DiskPath = Join-Path $VmsDir "$PfSenseVmName\$PfSenseVmName.vdi"
    & $VBoxManage createmedium disk --filename $DiskPath --size 8192 --format VDI | Out-Null
    
    # Adicionar controladora SATA e anexar o disco
    & $VBoxManage storagectl $PfSenseVmName --name "SATA Controller" --add sata --controller IntelAHCI | Out-Null
    & $VBoxManage storageattach $PfSenseVmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $DiskPath | Out-Null
    
    # Adicionar controladora IDE e anexar a ISO do pfSense
    & $VBoxManage storagectl $PfSenseVmName --name "IDE Controller" --add ide | Out-Null
    & $VBoxManage storageattach $PfSenseVmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $PfSenseIso | Out-Null
    
    Write-Host "VM '$PfSenseVmName' criada com sucesso!" -ForegroundColor Green
}

# 4. Criação da VM LAN-Client-Alpine
Write-Host "`n=== 3. Provisionando a VM LAN-Client-Alpine ===" -ForegroundColor Green
$AlpineVmName = "LAN-Client-Alpine"

if ($VmList -match $AlpineVmName) {
    Write-Host "A VM '$AlpineVmName' já existe no VirtualBox. Pulando criação." -ForegroundColor Yellow
} else {
    Write-Host "Criando a VM '$AlpineVmName'..." -ForegroundColor Cyan
    
    # Criar VM e registrar no workspace
    & $VBoxManage createvm --name $AlpineVmName --ostype "Linux_64" --register --basefolder $VmsDir | Out-Null
    
    # Configurar CPU, RAM, Vídeo (Alpine virtual precisa de muito pouco - 256MB RAM é suficiente)
    & $VBoxManage modifyvm $AlpineVmName --memory 256 --cpus 1 --vram 16 | Out-Null
    
    # Configurar Adaptador de Rede:
    # Adaptador 1: LAN -> Rede Interna (intnet) - mesmo switch do pfSense LAN
    & $VBoxManage modifyvm $AlpineVmName --nic1 intnet --intnet1 "intnet" | Out-Null
    
    # Criar disco virtual de 2GB (Alpine roda em RAM, mas criamos o disco por garantia)
    $DiskPathAlpine = Join-Path $VmsDir "$AlpineVmName\$AlpineVmName.vdi"
    & $VBoxManage createmedium disk --filename $DiskPathAlpine --size 2048 --format VDI | Out-Null
    
    # Adicionar controladora SATA e anexar o disco
    & $VBoxManage storagectl $AlpineVmName --name "SATA Controller" --add sata --controller IntelAHCI | Out-Null
    & $VBoxManage storageattach $AlpineVmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $DiskPathAlpine | Out-Null
    
    # Adicionar controladora IDE e anexar a ISO do Alpine
    & $VBoxManage storagectl $AlpineVmName --name "IDE Controller" --add ide | Out-Null
    & $VBoxManage storageattach $AlpineVmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $AlpineIso | Out-Null
    
    Write-Host "VM '$AlpineVmName' criada com sucesso!" -ForegroundColor Green
}

Write-Host "`n=== Laboratório Provisionado com Sucesso! ===" -ForegroundColor Green
Write-Host "Instruções Próximas:"
Write-Host "1. Inicie a VM do pfSense para a instalação gráfica:"
Write-Host "   & '$VBoxManage' startvm pfSense-VPN"
Write-Host "2. Quando terminar a instalação do pfSense e definir os IPs, inicie o cliente de forma invisível (headless):"
Write-Host "   & '$VBoxManage' startvm LAN-Client-Alpine --type headless"
