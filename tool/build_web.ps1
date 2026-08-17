param(
  [switch]$NoWasm
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot '.env'
$flutter = if (Test-Path 'C:\flutter\bin\flutter.bat') {
  'C:\flutter\bin\flutter.bat'
} else {
  (Get-Command flutter -ErrorAction Stop).Source
}

if (-not (Test-Path -LiteralPath $envFile)) {
  throw '.env 파일이 없습니다. .env.example을 복사한 뒤 값을 채워 주세요.'
}

$requiredKeys = @(
  'SUPABASE_URL',
  'SUPABASE_PUBLISHABLE_KEY',
  'YOUTUBE_API_KEY'
)
$definedKeys = Get-Content -LiteralPath $envFile |
  Where-Object { $_ -match '^\s*[^#][^=]*=' } |
  ForEach-Object { ($_.Split('=', 2)[0]).Trim() }
$missingKeys = $requiredKeys | Where-Object { $_ -notin $definedKeys }
if ($missingKeys.Count -gt 0) {
  throw ".env 필수 항목이 없습니다: $($missingKeys -join ', ')"
}

Push-Location $projectRoot
try {
  $arguments = @(
    'build',
    'web',
    '--release',
    '--dart-define-from-file=.env'
  )
  if (-not $NoWasm) {
    $arguments += '--wasm'
  }
  & $flutter @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter 웹 빌드가 종료 코드 $LASTEXITCODE 로 실패했습니다."
  }
} finally {
  Pop-Location
}
