#Requires -Version 5.0
<#
.SYNOPSIS
    Search for text content in files across a folder and its subfolders.

.DESCRIPTION
    Interactively prompts for a folder path and search term(s), then searches
    through supported file types (.ps1, .py, .md, .txt, .cs, .json, .xml, etc.)
    and displays all matching lines with file paths and line numbers.

.EXAMPLE
    .\Search-Content.ps1
#>

function Search-FileContent {
    param(
        [string]$FolderPath,
        [string]$SearchTerm
    )

    # File types to search
    $fileExtensions = @(
        '*.ps1', '*.py', '*.md', '*.txt', '*.csv',
        '*.cs', '*.js', '*.ts', '*.jsx', '*.tsx', '*.json',
        '*.xml', '*.yaml', '*.yml', '*.html', '*.css',
        '*.java', '*.cpp', '*.c', '*.h', '*.hpp', '*.go', '*.rb', '*.php',
        '*.sh', '*.bash', '*.bat', '*.cmd', '*.cfg', '*.conf', '*.config',
        '*.log', '*.sql', '*.vb', '*.swift', '*.kt', '*.rs', '*.toml'
    )

    $allResults = @()
    $filesSearched = 0
    $totalMatches = 0

    Write-Host "`nSearching..." -ForegroundColor DarkGray

    # Search each file type
    foreach ($extension in $fileExtensions) {
        try {
            $files = @(Get-ChildItem -Path $FolderPath -Filter $extension -File -Recurse -ErrorAction SilentlyContinue)

            foreach ($file in $files) {
                $filesSearched++

                # Search using Select-String (case-insensitive)
                $matches = Select-String -Path $file.FullName -Pattern $SearchTerm -ErrorAction SilentlyContinue

                if ($matches) {
                    $totalMatches += @($matches).Count
                    $allResults += $matches
                }
            }
        } catch {
            # Skip files that can't be read
        }
    }

    return @{
        Results = $allResults
        FilesSearched = $filesSearched
        MatchCount = $totalMatches
    }
}

# Main script
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "    File Content Search Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Function to get path with autocomplete suggestions
function Get-PathInput {
    param([string]$Prompt)

    Write-Host "`n$Prompt" -ForegroundColor Yellow

    $pathValid = $false
    while (-not $pathValid) {
        $inputPath = Read-Host

        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            Write-Host "ERROR: Path cannot be empty. Try again." -ForegroundColor Red
            continue
        }

        # Handle quotes if user included them
        $inputPath = $inputPath.Trim('"', "'")

        # Expand environment variables and resolve path
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($inputPath)

        if (-not (Test-Path $expandedPath -PathType Container)) {
            Write-Host "ERROR: Folder not found or not accessible." -ForegroundColor Red

            # Try to suggest similar paths
            $parent = Split-Path -Parent $expandedPath
            if (Test-Path $parent -PathType Container) {
                Write-Host "Did you mean one of these?" -ForegroundColor Gray
                Get-ChildItem -Path $parent -Directory -ErrorAction SilentlyContinue |
                    Select-Object -First 5 |
                    ForEach-Object { Write-Host "  > $($_.FullName)" -ForegroundColor Gray }
            }
            Write-Host "Try again:" -ForegroundColor Yellow
        } else {
            return $expandedPath
        }
    }
}

# Get folder path
$folderPath = Get-PathInput "Enter folder path to search:"

# Get search term
Write-Host "`nEnter search term(s) (use quotes for multiple words):" -ForegroundColor Yellow
$searchTerm = Read-Host

if ([string]::IsNullOrWhiteSpace($searchTerm)) {
    Write-Host "`nERROR: Search term cannot be empty." -ForegroundColor Red
    exit 1
}

# Remove surrounding quotes if present
$searchTerm = $searchTerm.Trim('"', "'")

Write-Host ""
Write-Host "Searching in: $folderPath" -ForegroundColor White
Write-Host "Search term: `"$searchTerm`"" -ForegroundColor White

# Perform search
$searchResults = Search-FileContent -FolderPath $folderPath -SearchTerm $searchTerm

# Display results
Write-Host "`n------------------------------------------------------------" -ForegroundColor Gray

if ($searchResults.MatchCount -eq 0) {
    Write-Host "No matches found." -ForegroundColor Yellow
} else {
    Write-Host "Found $($searchResults.MatchCount) match(es) in files:" -ForegroundColor Green
    Write-Host ""

    # Group results by file for cleaner display
    $grouped = $searchResults.Results | Group-Object Path

    foreach ($group in $grouped) {
        $filePath = $group.Name
        $relativePath = if ($filePath.StartsWith($folderPath)) {
            $filePath.Substring($folderPath.Length).TrimStart('\', '/')
        } else {
            $filePath
        }

        Write-Host "FILE: $relativePath" -ForegroundColor Cyan

        $group.Group | ForEach-Object {
            $line = $_.Line.Trim()
            if ($line.Length -gt 100) {
                $line = $line.Substring(0, 97) + "..."
            }
            Write-Host "  Line $($_.LineNumber): $line" -ForegroundColor White
        }
        Write-Host ""
    }
}

Write-Host "------------------------------------------------------------" -ForegroundColor Gray
Write-Host "Summary: $($searchResults.FilesSearched) files searched, $($searchResults.MatchCount) matches found" -ForegroundColor Green
Write-Host ""

# Loop for multiple searches
$continueSearching = $true
while ($continueSearching) {
    Write-Host "Search again?" -ForegroundColor Yellow
    Write-Host "[S]ame folder, [N]ew folder, [Q]uit" -ForegroundColor Gray
    $choice = Read-Host "Enter choice (S/N/Q)"

    switch ($choice.ToUpper()) {
        "S" {
            Write-Host "`nEnter new search term(s):" -ForegroundColor Yellow
            $searchTerm = Read-Host

            if ([string]::IsNullOrWhiteSpace($searchTerm)) {
                Write-Host "ERROR: Search term cannot be empty." -ForegroundColor Red
                continue
            }

            $searchTerm = $searchTerm.Trim('"', "'")

            Write-Host ""
            Write-Host "Searching in: $folderPath" -ForegroundColor White
            Write-Host "Search term: `"$searchTerm`"" -ForegroundColor White

            $searchResults = Search-FileContent -FolderPath $folderPath -SearchTerm $searchTerm

            Write-Host "`n------------------------------------------------------------" -ForegroundColor Gray

            if ($searchResults.MatchCount -eq 0) {
                Write-Host "No matches found." -ForegroundColor Yellow
            } else {
                Write-Host "Found $($searchResults.MatchCount) match(es) in files:" -ForegroundColor Green
                Write-Host ""

                $grouped = $searchResults.Results | Group-Object Path

                foreach ($group in $grouped) {
                    $filePath = $group.Name
                    $relativePath = if ($filePath.StartsWith($folderPath)) {
                        $filePath.Substring($folderPath.Length).TrimStart('\', '/')
                    } else {
                        $filePath
                    }

                    Write-Host "FILE: $relativePath" -ForegroundColor Cyan

                    $group.Group | ForEach-Object {
                        $line = $_.Line.Trim()
                        if ($line.Length -gt 100) {
                            $line = $line.Substring(0, 97) + "..."
                        }
                        Write-Host "  Line $($_.LineNumber): $line" -ForegroundColor White
                    }
                    Write-Host ""
                }
            }

            Write-Host "------------------------------------------------------------" -ForegroundColor Gray
            Write-Host "Summary: $($searchResults.FilesSearched) files searched, $($searchResults.MatchCount) matches found" -ForegroundColor Green
            Write-Host ""
        }
        "N" {
            $folderPath = Get-PathInput "Enter new folder path to search:"

            Write-Host "`nEnter search term(s):" -ForegroundColor Yellow
            $searchTerm = Read-Host

            if ([string]::IsNullOrWhiteSpace($searchTerm)) {
                Write-Host "ERROR: Search term cannot be empty." -ForegroundColor Red
                continue
            }

            $searchTerm = $searchTerm.Trim('"', "'")

            Write-Host ""
            Write-Host "Searching in: $folderPath" -ForegroundColor White
            Write-Host "Search term: `"$searchTerm`"" -ForegroundColor White

            $searchResults = Search-FileContent -FolderPath $folderPath -SearchTerm $searchTerm

            Write-Host "`n------------------------------------------------------------" -ForegroundColor Gray

            if ($searchResults.MatchCount -eq 0) {
                Write-Host "No matches found." -ForegroundColor Yellow
            } else {
                Write-Host "Found $($searchResults.MatchCount) match(es) in files:" -ForegroundColor Green
                Write-Host ""

                $grouped = $searchResults.Results | Group-Object Path

                foreach ($group in $grouped) {
                    $filePath = $group.Name
                    $relativePath = if ($filePath.StartsWith($folderPath)) {
                        $filePath.Substring($folderPath.Length).TrimStart('\', '/')
                    } else {
                        $filePath
                    }

                    Write-Host "FILE: $relativePath" -ForegroundColor Cyan

                    $group.Group | ForEach-Object {
                        $line = $_.Line.Trim()
                        if ($line.Length -gt 100) {
                            $line = $line.Substring(0, 97) + "..."
                        }
                        Write-Host "  Line $($_.LineNumber): $line" -ForegroundColor White
                    }
                    Write-Host ""
                }
            }

            Write-Host "------------------------------------------------------------" -ForegroundColor Gray
            Write-Host "Summary: $($searchResults.FilesSearched) files searched, $($searchResults.MatchCount) matches found" -ForegroundColor Green
            Write-Host ""
        }
        "Q" {
            Write-Host "`nGoodbye!" -ForegroundColor Cyan
            $continueSearching = $false
        }
        default {
            Write-Host "Invalid choice. Please enter S, N, or Q." -ForegroundColor Red
        }
    }
}
