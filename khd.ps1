# Original author and source code: https://github.com/Mahtwo/KHDownloader
# SPDX-License-Identifier: MPL-2.0

<#
.SYNOPSIS
Downloads an album from KHInsider Video Game Music with resuming functionality.

.DESCRIPTION
The khd.ps1 script downloads an album from the KHInsider Video Game Music website
specified by the user. If the script stops for any reason, it will resume where
it previously was when run again with the same album.

.PARAMETER Url
URL of the KHInsider album to download
(like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album).

.PARAMETER Format
Audio format to prioritize (like FLAC, M4A, etc.), if not available will fallback to MP3.
This parameter supports tab completion based on the value of the URL parameter.

.INPUTS
None. You can't pipe objects to khd.ps1.

.OUTPUTS
None. khd.ps1 doesn't generate any output to the pipeline.

.EXAMPLE
& khd.ps1 https://downloads.khinsider.com/game-soundtracks/album/the-legend-of-zelda-breath-of-the-wild

.EXAMPLE
& khd.ps1 https://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017 m4a

.LINK
https://downloads.khinsider.com/
#>

#Requires -PSEdition Core
# Suppress some PSScript-Analyzer warnings
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'commandAst', Justification = 'variable not used in ArgumentCompleter of formats')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'commandName', Justification = 'variable not used in ArgumentCompleter of formats')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'parameterName', Justification = 'variable not used in ArgumentCompleter of formats')]
# TODO : For Linux compatibility, New-Object -Com 'HTMLFile' will need to be replaced with an Install-Module/#Requires -Module)

param (
	[Parameter(Position = 0, Mandatory, HelpMessage = 'URL of the album to download (like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album)')]
	[Alias('u')]
	[ValidateScript({
			if ($_ -notmatch '^(https?://)?downloads.khinsider.com/game-soundtracks/album/[^/]+$') {
				throw 'Invalid URL, it should look like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album'
			}

			if ($null -eq $_.Scheme) {
				[uri]$validateScriptUrl = "https://$_"
			}
			else {
				[uri]$validateScriptUrl = $_
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($validateScriptUrl.Segments[-1] + '.html')
			# Skip check if main page HTML file already exist
			if (Test-Path -PathType Leaf $mainPageFile) {
				return $true
			}

			# Check internet by trying to connect to the URL
			if (-not (Test-Connection $validateScriptUrl.Host -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
				throw "$($validateScriptUrl.Host) is unreachable, check your internet connection."
			}

			# The file will only be created after downlading it entirely
			$mainPage = (Invoke-WebRequest -PassThru -ErrorAction Stop -OutFile $mainPageFile $validateScriptUrl).Content
			# Check if the URL is a valid album URL
			if ($mainPage -match '<title>\s*Error\s*<\/title>') {
				Remove-Item -LiteralPath $mainPageFile
				throw "The album $_ does not exist"
			}

			return $true
		}
	)]
	[uri]$Url,

	[Parameter(Position = 1, HelpMessage = 'Audio format to prioritize (like FLAC, M4A, etc.), if not available will fallback to MP3')]
	[Alias('f')]
	[ArgumentCompletions('')] # Disable suggesting files from working directory when ArgumentCompleter returns nothing
	# Returning MP3 is technically useless but it's helpful for users not knowing MP3 is always available
	# Returning MP3 also tells the user formats have been gotten correctly when it's the only format available
	[ArgumentCompleter({
			param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
			if (-not $fakeBoundParameters.ContainsKey('Url')) {
				return
			}

			if ($null -eq $fakeBoundParameters['Url'].Scheme) {
				[uri]$argumentCompleterUrl = "https://$($fakeBoundParameters['Url'])"
			}
			else {
				[uri]$argumentCompleterUrl = $fakeBoundParameters['Url']
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($argumentCompleterUrl.Segments[-1] + '.html')
			if (Test-Path -PathType Leaf $mainPageFile) {
				$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
			}
			else {
				# Will silently fail if no internet connection (which is what we want)
				$mainPage = (Invoke-WebRequest -PassThru -ErrorAction Stop -OutFile $mainPageFile $argumentCompleterUrl).Content
			}
			# Check if the URL is a valid album URL
			if ($mainPage -match '<title>\s*Error\s*<\/title>') {
				return
			}

			$MainPageHtml = New-Object -Com 'HTMLFile'
			$MainPageHtml.write([System.Text.Encoding]::Unicode.GetBytes($mainPage))
			$tableHeader = $MainPageHtml.getElementById('songlist_header').children
			$availableFormats = @()
			for ($i = $tableHeader.Length - 3; $tableHeader[$i].innerText -ne 'Song Name'; $i--) {
				$availableFormats += $tableHeader[$i].innerText
			}
			[array]::Reverse($availableFormats)

			if ($wordToComplete) {
				return $availableFormats | Where-Object { $_ -like "$wordToComplete*" }
			}
			else {
				return $availableFormats
			}
		}
	)]
	[string]$Format = 'MP3'
)

## FORMATTING ARGUMENTS
if ($null -eq $url.Scheme) {
	$url = "https://$url"
}
$format = $format.ToUpperInvariant() # No null check needed as a string cannot be null

## GET ALBUM NAME
# Main page HTML file already exist because of argument URL ValidateScript
$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($url.Segments[-1] + '.html')
$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
$MainPageHtml = New-Object -Com 'HTMLFile'
$MainPageHtml.write([System.Text.Encoding]::Unicode.GetBytes($mainPage))
# Replace illegal path characters and consecutive spaces to one space
$albumName = $MainPageHtml.GetElementsByTagName('h2')[0].innerText -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '

## GET ALL SONGS PAGE URL
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ($url.Segments[-1] + '.khd')
if (-not (Test-Path -PathType Leaf $tempFile)) {
	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status 'Getting each song page URL' -PercentComplete 0

	# Get page URL of each song
	$playlistDownloadSong = $MainPageHtml.GetElementsByClassName('playlistDownloadSong')
	$pDSLength = $playlistDownloadSong.Length
	$songsPageURL = [string[]]::new($pDSLength)
	for ($index = 0; $index -lt $pDSLength; $index++) {
		Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete ([math]::Floor($index / $pDSLength * 10))
		$songPageURL = ($playlistDownloadSong[$index].GetElementsByTagName('a'))[0].href
		$songPageURL = $songPageURL -replace '^about:', $url.GetLeftPart([System.UriPartial]::Authority)
		$songsPageURL[$index] = $songPageURL
	}

	# Create file containing all songs page URLs
	foreach ($songPageURL in $songsPageURL) {
		Add-Content -LiteralPath $tempFile -Value $songPageURL
	}

	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete 10
}
else {
	$songsPageURL = Get-Content -LiteralPath $tempFile
}

## CONVERT ALL SONGS PAGE URL TO SONGS URL
$songsURL = $songsPageURL
if ($songsURL[-1].Contains('downloads.khinsider.com/game-soundtracks/album/')) {
	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status 'Converting each song page URL to download URL' -PercentComplete 10

	if ($format -ne 'MP3') {
		# Check if the format is available for this album
		$formatAvailable = $false
		$tableHeader = $MainPageHtml.getElementById('songlist_header').children
		for ($i = $tableHeader.Length - 3; $tableHeader[$i].innerText -ne 'Song Name'; $i--) {
			if ($tableHeader[$i].innerText -eq $Format) {
				$formatAvailable = $true
				break
			}
		}
		if (-not $formatAvailable) {
			$format = 'MP3'
		}
	}

	$sPULength = $songsPageURL.Length
	try {
		for ($index = 0; $index -lt $sPULength; $index++) {
			Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status "Converting each song page URL to download URL ($index/$sPULength)" -PercentComplete (10 + [math]::Floor($index / $sPULength * 10))
			$songPageURL = $songsPageURL[$index]
			if (-not $songPageURL.Contains('downloads.khinsider.com/game-soundtracks/album/')) {
				# Skip URLs already converted
				continue
			}

			$SongPage = (Invoke-WebRequest -ErrorAction Stop $songPageURL).Content
			$songPageHtml = New-Object -Com 'HTMLFile'
			$songPageHtml.write([System.Text.Encoding]::Unicode.GetBytes($SongPage))
			$songDownloadLinks = $songPageHtml.GetElementsByClassName('songDownloadLink')

			# Check if format is available (the format may not be available for every song)
			$formatFound = $false
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.innerText.EndsWith($format)) {
					$songsURL[$index] = $songDownloadLink.parentElement.href
					$formatFound = $true
					break
				}
			}
			if ($formatFound) {
				continue
			}

			# Fallback to MP3
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.innerText.EndsWith('MP3')) {
					$href = $songDownloadLink.parentElement.href
					$songsURL[$index] = $href
					# Prettify filename without extension from URL for warning
					$filename = [uri]::UnescapeDataString(((Split-Path -LeafBase $href) -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '))
					Write-Warning "Format $format not found for $filename, fallbacking to MP3"
					break
				}
			}
		}
	}
	catch {
		# Necessary to exit script on all errors, otherwise some errors (notably from Invoke-WebRequest) continue after finally
		# The catch can be removed when/if https://github.com/PowerShell/PowerShell/issues/21345 is fixed
		throw $_
	}
	finally {
		# Save current progress even on errors or Ctrl-C
		$tempFileTemp = "$tempFile.tmp"
		New-Item -ItemType File -Force $tempFileTemp > $null
		foreach ($songURL in $songsURL) {
			Add-Content -LiteralPath $tempFileTemp -Value $songURL
		}
		Move-Item -Force -LiteralPath $tempFileTemp -Destination $tempFile
	}

	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status "Converting each song page URL to download URL ($index/$sPULength)" -PercentComplete 20
}
elseif ($format -ne 'MP3') {
	Write-Warning "All songs URL are present, format $format will not be checked"
}

## PREPARE FILENAMES FROM SONGS URL
$sULength = $songsURL.Length
$songsFile = [string[]]::new($sULength)
for ($index = 0; $index -lt $sULength; $index++) {
	$songURL = $songsURL[$index]
	$filename = [uri]::UnescapeDataString(((Split-Path -Leaf $songURL) -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '))
	$filepath = Join-Path -Path $pwd -ChildPath $albumName -AdditionalChildPath $filename
	$songsFile[$index] = $filepath
}

## DOWNLOADING EACH SONG
if (-not (Test-Path -PathType Container $albumName)) {
	New-Item -ItemType Directory $albumName > $null
}
for ($index = 0; $index -lt $sULength; $index++) {
	# Skip to the last downloaded file as it may only be partially downloaded
	if ($index + 1 -ne $sULength -and (Test-Path -PathType Leaf $songsFile[$index + 1])) {
		continue
	}
	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status "Downloading each song ($index/$sULength)" -PercentComplete (20 + [math]::Floor($index / $sULength * 80))

	$songURL = $songsURL[$index]
	$songFile = $songsFile[$index]
	try {
		Invoke-WebRequest -Resume -ErrorAction Stop -OutFile $songFile $songURL > $null
	}
	catch {
		# Necessary to exit on Invoke-WebRequest error, otherwise those errors don't end the script
		# The try-catch can be removed (keep only the Invoke-WebRequest command) when/if https://github.com/PowerShell/PowerShell/issues/21345 is fixed
		throw $_
	}
}

## CLEAN-UP
Remove-Item -LiteralPath $mainPageFile, $tempFile
if ($ProgressPreference -ne 'SilentlyContinue' -and $ProgressPreference -ne 'Ignore') {
	# Add a delay to show 100% complete bar for better UX
	# Write-Progress only update every 200ms and does not update to the last "missed" Write-Progress even after 200ms
	Start-Sleep -Milliseconds 200
	Write-Progress -Id 23 -Activity "Downloading album $albumName" -Status 'Done!' -PercentComplete 100
	Start-Sleep 1
}
Write-Progress -Id 23 -Completed