$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$blogsDir = Join-Path $repoRoot "blogs"
$notesDir = Join-Path $repoRoot "notes"
$contentDir = Join-Path $repoRoot "content"

New-Item -ItemType Directory -Force -Path $contentDir | Out-Null

function Convert-NameToTitle([string]$name) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $base = $base -replace "[-_]+", " "
  return [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($base.ToLower())
}

function Get-PageTitle([string]$filePath, [string]$fallback) {
  $text = Get-Content -Raw -Path $filePath
  $h1 = [regex]::Match($text, "<h1[^>]*>\s*(.*?)\s*</h1>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($h1.Success) { return $h1.Groups[1].Value }
  $title = [regex]::Match($text, "<title[^>]*>\s*(.*?)\s*</title>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($title.Success) { return $title.Groups[1].Value }
  return $fallback
}

$blogs = Get-ChildItem -Path $blogsDir -File -Filter *.html | Sort-Object LastWriteTime -Descending | ForEach-Object {
  $fallback = Convert-NameToTitle $_.Name
  [PSCustomObject]@{
    path = "blogs/$($_.Name)"
    title = Get-PageTitle -filePath $_.FullName -fallback $fallback
    description = "HTML blog post"
    date = $_.LastWriteTime.ToString("yyyy-MM-dd")
  }
}

$notes = Get-ChildItem -Path $notesDir -File -Filter *.pdf | Sort-Object LastWriteTime -Descending | ForEach-Object {
  [PSCustomObject]@{
    path = "notes/$($_.Name)"
    title = Convert-NameToTitle $_.Name
    description = "PDF note"
    date = $_.LastWriteTime.ToString("yyyy-MM-dd")
  }
}

@($blogs) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $contentDir "blogs.json")
@($notes) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $contentDir "notes.json")

Write-Host "Updated content/blogs.json and content/notes.json"
