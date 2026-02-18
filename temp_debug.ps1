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

function Get-PageTags([string]$filePath) {
  $text = Get-Content -Raw -Path $filePath
  $meta = [regex]::Match(
    $text,
    '<meta\s+name\s*=\s*["'']tags["'']\s+content\s*=\s*["'']([^"'']+)["'']',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
  if (-not $meta.Success) { return @() }
  return @(
    ($meta.Groups[1].Value -split ",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -ne "" } |
      Select-Object -Unique
  )
}

function Get-RelativePath([string]$basePath, [string]$targetPath) {
  $resolvedBase = (Resolve-Path $basePath).Path.TrimEnd("\")
  $resolvedTarget = (Resolve-Path $targetPath).Path
  $baseUri = New-Object System.Uri(($resolvedBase + "\"))
  $targetUri = New-Object System.Uri($resolvedTarget)
  $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
  return ([System.Uri]::UnescapeDataString($relative) -replace "/", "/")
}

function To-RepoRelativePath([string]$root, [string]$fullPath) {
  return Get-RelativePath -basePath $root -targetPath $fullPath
}

function Get-SectionLabel([string]$id) {
  switch ($id.ToLower()) {
    "general" { return "General" }
    "year2" { return "Year 2" }
    "year3" { return "Year 3" }
    default { return (Convert-NameToTitle $id) }
  }
}

function Get-CourseLabel([string]$code) {
  if ($code -match "^[a-z]{2,}\d{2,}$") { return $code.ToUpper() }
  $clean = $code -replace "[-_]+", " "
  return [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($clean.ToLower())
}

$blogs = Get-ChildItem -Path $blogsDir -File -Filter *.html | Sort-Object LastWriteTime -Descending | ForEach-Object {
  $fallback = Convert-NameToTitle $_.Name
  [PSCustomObject]@{
    path = "blogs/$($_.Name)"
    title = Get-PageTitle -filePath $_.FullName -fallback $fallback
    description = "HTML blog post"
    date = $_.LastWriteTime.ToString("yyyy-MM-dd")
    tags = Get-PageTags -filePath $_.FullName
  }
}

$noteFiles = Get-ChildItem -Path $notesDir -File -Recurse | Sort-Object LastWriteTime -Descending

$notes = $noteFiles | ForEach-Object {
  $ext = $_.Extension.TrimStart(".").ToUpper()
  [PSCustomObject]@{
    path = To-RepoRelativePath -root $repoRoot -fullPath $_.FullName
    title = Convert-NameToTitle $_.Name
    description = "$ext document"
    date = $_.LastWriteTime.ToString("yyyy-MM-dd")
  }
}

$sectionOrder = @("general", "year2", "year3")
$noteSections = [System.Collections.Generic.List[object]]::new()
$sectionLookup = @{}

foreach ($sectionId in $sectionOrder) {
  $sectionObj = [ordered]@{
    id = $sectionId
    label = Get-SectionLabel $sectionId
    courses = @()
  }
  $sectionLookup[$sectionId] = $sectionObj
  $noteSections.Add($sectionObj)
}

# Also include any extra first-level folders under notes/ that are outside general/year2/year3.
Get-ChildItem -Path $notesDir -Directory | ForEach-Object {
  $id = $_.Name.ToLower()
  if (-not $sectionLookup.ContainsKey($id)) {
    $sectionObj = [ordered]@{
      id = $id
      label = Get-SectionLabel $id
      courses = @()
    }
    $sectionLookup[$id] = $sectionObj
    $noteSections.Add($sectionObj)
  }
}

foreach ($file in $noteFiles) {
  $relativeFromNotes = Get-RelativePath -basePath $notesDir -targetPath $file.FullName
  $parts = @($relativeFromNotes -split "/")
  if ($parts.Count -eq 0) { continue }

  $sectionId = "general"
  $courseCode = "general"

  if ($parts.Count -ge 3) {
    $sectionId = $parts[0].ToLower()
    $courseCode = $parts[1]
  } elseif ($parts.Count -eq 2) {
    # Example: notes/year2/file.pdf OR notes/course/file.pdf
    $head = $parts[0].ToLower()
    if ($sectionLookup.ContainsKey($head)) {
      $sectionId = $head
      $courseCode = "general"
    } else {
      $sectionId = "general"
      $courseCode = $parts[0]
    }
  }

  if (-not $sectionLookup.ContainsKey($sectionId)) {
    $sectionObj = [ordered]@{
      id = $sectionId
      label = Get-SectionLabel $sectionId
      courses = @()
    }
    $sectionLookup[$sectionId] = $sectionObj
    $noteSections.Add($sectionObj)
  }

  $section = $sectionLookup[$sectionId]
  $course = $section.courses | Where-Object { $_.code -eq $courseCode } | Select-Object -First 1
  if (-not $course) {
    $course = [ordered]@{
      code = $courseCode
      label = Get-CourseLabel $courseCode
      documents = @()
    }
    $section.courses += $course
  }

  $course.documents += [ordered]@{
    path = To-RepoRelativePath -root $repoRoot -fullPath $file.FullName
    title = Convert-NameToTitle $file.Name
    date = $file.LastWriteTime.ToString("yyyy-MM-dd")
    type = $file.Extension.TrimStart(".").ToUpper()
  }
}

@($blogs) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $contentDir "blogs.json")
@($notes) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $contentDir "notes.json")
@($noteSections) | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $contentDir "notes-tree.json")

Write-Host "Updated content/blogs.json, content/notes.json, and content/notes-tree.json"

