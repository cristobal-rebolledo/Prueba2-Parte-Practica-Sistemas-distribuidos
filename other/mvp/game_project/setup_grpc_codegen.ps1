# Script de setup para desarrolladores Elixir: gRPC codegen
# Ejecuta esto en PowerShell antes de trabajar con el proyecto
# Deja el entorno listo para compilar y usar gRPC con Elixir

# 1. Añadir escripts de mix al PATH de usuario permanentemente y para la sesión actual
$mixEscripts = "$env:USERPROFILE\.mix\escripts"
$envPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $envPath.Split(';') -contains $mixEscripts) {
    [System.Environment]::SetEnvironmentVariable('Path', "$envPath;$mixEscripts", 'User')
    Write-Host "[OK] PATH actualizado para incluir: $mixEscripts (permanente)"
} else {
    Write-Host "[OK] PATH ya contiene: $mixEscripts (permanente)"
}
# Asegura que el path esté en la sesión actual también
if (-not $env:Path.Split(';') -contains $mixEscripts) {
    $env:Path += ";$mixEscripts"
    Write-Host "[OK] PATH actualizado para la sesión actual: $mixEscripts"
} else {
    Write-Host "[OK] PATH ya presente en la sesión actual: $mixEscripts"
}

# 2. Instalar plugin protobuf si no existe
if (-not (Get-Command protoc-gen-elixir -ErrorAction SilentlyContinue)) {
    Write-Host "[INFO] Instalando plugin Elixir para Protobuf..."
    mix escript.install hex protobuf
} else {
    Write-Host "[OK] Plugin protoc-gen-elixir ya instalado."
}

# 3. Detectar Windows 64 y usar bin/protoc.exe si existe
$protocCmd = "protoc"
if ($env:OS -eq "Windows_NT" -and [Environment]::Is64BitOperatingSystem) {
    $localProtoc = Join-Path $PSScriptRoot "bin/protoc.exe"
    if (Test-Path $localProtoc) {
        $protocCmd = $localProtoc
        Write-Host "[OK] Usando binario local: $protocCmd"
    } else {
        Write-Host "[WARN] No se encontró bin/protoc.exe, se usará el del PATH si existe."
    }
}

# 4. Verificar que protoc está instalado
if (-not (Get-Command $protocCmd -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Debes instalar 'protoc' (Protocol Buffers Compiler) y reiniciar la terminal, o colocar protoc.exe en bin/."
    exit 1
}

# 5. Generar los archivos .pb.ex desde log.proto
$protoPath = "../../proto_server/log.proto"
$outDir = "./lib/game_project"
# Usar ruta absoluta al plugin
$elixirPlugin = "$mixEscripts\protoc-gen-elixir.bat"
Write-Host "[INFO] Usando plugin en: $elixirPlugin"
Write-Host "[INFO] Generando archivos Elixir desde $protoPath ..."

# En Windows, protoc necesita la ruta completa al plugin
if ($env:OS -eq "Windows_NT") {
    $env:PROTOC_GEN_ELIXIR = $elixirPlugin
    & $protocCmd --plugin=protoc-gen-elixir="$elixirPlugin" --elixir_out=plugins=grpc:$outDir --proto_path=../../proto_server $protoPath
} else {
    & $protocCmd --elixir_out=plugins=grpc:$outDir --proto_path=../../proto_server $protoPath
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Archivos .pb.ex generados en $outDir"
} else {
    Write-Host "[ERROR] Falló la generación de archivos .pb.ex"
    exit 1
}

Write-Host "[SETUP COMPLETO] Puedes compilar y correr el proyecto con gRPC real."
