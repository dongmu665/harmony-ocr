param(
  [string]$ImagePath = "",
  [string]$Language = "en",
  [switch]$Health
)

# 中文说明：该脚本只桥接 Windows.Media.Ocr，不保存图片、不记录 OCR 全文、不访问网络或第三方服务。
$ErrorActionPreference = "Stop"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8Line {
  param(
    [AllowNull()][string]$Text = ""
  )
  $line = if ($null -eq $Text) { "" } else { $Text }
  $bytes = $script:Utf8NoBom.GetBytes($line + [Environment]::NewLine)
  $stdout = [Console]::OpenStandardOutput()
  try {
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
  } finally {
    $stdout.Dispose()
  }
}

function Write-Utf8ErrorLine {
  param(
    [AllowNull()][string]$Text = ""
  )
  $line = if ($null -eq $Text) { "Windows OCR failed" } else { $Text }
  $bytes = $script:Utf8NoBom.GetBytes($line + [Environment]::NewLine)
  $stderr = [Console]::OpenStandardError()
  try {
    $stderr.Write($bytes, 0, $bytes.Length)
    $stderr.Flush()
  } finally {
    $stderr.Dispose()
  }
}

function Await-WinRt {
  param(
    [object]$Operation,
    [type]$ResultType
  )
  $method = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
      $_.Name -eq "AsTask" -and
      $_.GetParameters().Count -eq 1 -and
      $_.IsGenericMethodDefinition
    } |
    Select-Object -First 1).MakeGenericMethod($ResultType)
  $task = $method.Invoke($null, @($Operation))
  $task.Wait()
  return $task.Result
}

try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
  [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime] | Out-Null
  [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
  [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
  [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime] | Out-Null

  $lang = [Windows.Globalization.Language]::new($Language)
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
  if ($null -eq $engine) {
    Write-Utf8ErrorLine "Windows OCR engine unavailable for requested language"
    exit 1
  }
  if ($Health) {
    Write-Utf8Line "OK"
    exit 0
  }
  if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath)) {
    Write-Utf8ErrorLine "OCR image missing"
    exit 1
  }

  $file = Await-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
  $stream = Await-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result = Await-WinRt ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  Write-Utf8Line $result.Text
  exit 0
} catch {
  Write-Utf8ErrorLine "Windows OCR failed"
  exit 1
}
