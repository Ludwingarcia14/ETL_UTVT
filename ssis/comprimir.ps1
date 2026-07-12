param(
    [Parameter(Mandatory=$true)][string]$Origen,
    [Parameter(Mandatory=$true)][string]$Zip
)
try {
    $archivos = Get-ChildItem -Path $Origen -Filter *.csv -File
    if ($archivos.Count -eq 0) { Write-Output "No hay CSV que comprimir"; exit 0 }
    Compress-Archive -Path $archivos.FullName -DestinationPath $Zip -Force
    Write-Output "ZIP generado: $Zip"
    exit 0
} catch {
    Write-Error "Error al comprimir: $_"
    exit 1
}
