# SPDX-License-Identifier: MPL-2.0
# Original author and source code: https://github.com/Mahtwo/KHDownloader

<#
.SYNOPSIS
Downloads an album from KHInsider Video Game Music with robust resume functionality.

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

.PARAMETER NoCoverArt
Disables downloading the album cover art.

.INPUTS
None. You can't pipe objects to khd.ps1.

.OUTPUTS
None. khd.ps1 doesn't generate any output to the pipeline.

.EXAMPLE
& ./khd.ps1 https://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017 m4a

.EXAMPLE
$items = @(
	@{
		Url = 'https://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017'
		Format = 'm4a'
	},
	@{
		Url = 'https://downloads.khinsider.com/game-soundtracks/album/the-legend-of-zelda-breath-of-the-wild'
	}
)
foreach ($item in $items) {& ./khd.ps1 @item}

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
			} else {
				[uri]$validateScriptUrl = $_
			}

			# Check internet by trying to connect to the URL
			if (-not (Test-Connection $validateScriptUrl.Host -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
				throw "$($validateScriptUrl.Host) is unreachable, check your internet connection."
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($validateScriptUrl.Segments[-1] + '.html')
			# Skip check if main page HTML file already exist
			if (Test-Path -PathType Leaf $mainPageFile) {
				return $true
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

	[Parameter(Position = 1)]
	[Alias('f')]
	[ArgumentCompletions('')] # Disable suggesting files from working directory when ArgumentCompleter returns nothing
	# Returning MP3 is technically useless but it's helpful for users not knowing MP3 is always available
	# Returning MP3 also tells the user formats have been gotten correctly when it's the only format available
	[ArgumentCompleter({
			param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
			if (-not $fakeBoundParameters.ContainsKey('Url')) {
				return
			}

			# fakeBoundParameters values are of primitive types (string int etc.), so we cannot use Scheme property
			if ($fakeBoundParameters['Url'] -match '^https?') {
				[uri]$argumentCompleterUrl = $fakeBoundParameters['Url']
			} else {
				[uri]$argumentCompleterUrl = "https://$($fakeBoundParameters['Url'])"
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($argumentCompleterUrl.Segments[-1] + '.html')
			if (Test-Path -PathType Leaf $mainPageFile) {
				$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
			} else {
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
			} else {
				return $availableFormats
			}
		}
	)]
	[string]$Format = 'MP3',

	[Alias('nca')]
	[switch]$NoCoverArt
)

## FORMATTING ARGUMENTS
if ($null -eq $Url.Scheme) {
	$Url = "https://$Url"
}
$Format = $Format.ToUpperInvariant() # No null check needed as a string cannot be null

## GET ALBUM NAME
# Main page HTML file already exist because of argument URL ValidateScript
$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($Url.Segments[-1] + '.html')
$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
$MainPageHtml = New-Object -Com 'HTMLFile'
$MainPageHtml.write([System.Text.Encoding]::Unicode.GetBytes($mainPage))
# Replace illegal path characters and consecutive spaces to one space
$albumName = $MainPageHtml.GetElementsByTagName('h2')[0].innerText -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '

## GET ALL SONGS PAGE URL
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ($Url.Segments[-1] + '.khd')
if (-not (Test-Path -PathType Leaf $tempFile)) {
	Write-Progress -Activity "Downloading album $albumName" -Status 'Getting each song page URL' -PercentComplete 0

	# Get page URL of each song
	$playlistDownloadSong = $MainPageHtml.GetElementsByClassName('playlistDownloadSong')
	$pDSLength = $playlistDownloadSong.Length
	$songsURL = [string[]]::new($pDSLength)
	# Fast enough, parallelization would be slower
	for ($index = 0; $index -lt $pDSLength; $index++) {
		Write-Progress -Activity "Downloading album $albumName" -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete ([math]::Floor($index / $pDSLength * 5))
		$songPageURL = ($playlistDownloadSong[$index].GetElementsByTagName('a'))[0].href
		$songsURL[$index] = $songPageURL -replace '^about:', $Url.GetLeftPart([System.UriPartial]::Authority)
	}

	# Create file containing all songs page URLs
	foreach ($songPageURL in $songsURL) {
		Add-Content -LiteralPath $tempFile -Value $songPageURL
	}

	Write-Progress -Activity "Downloading album $albumName" -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete 5
} else {
	$songsURL = Get-Content -LiteralPath $tempFile
}

## CONVERT ALL SONGS PAGE URL TO SONGS URL
if (($songsURL -join '').Contains('downloads.khinsider.com/game-soundtracks/album/')) {
	Write-Progress -Activity "Downloading album $albumName" -Status 'Converting each song page URL to download URL' -PercentComplete 5

	if ($Format -ne 'MP3') {
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
			Write-Warning "${albumName}: Format $Format not available, fallbacking to MP3"
			$Format = 'MP3'
		}
	}

	$sULength = $songsURL.Length
	try {
		# We assume more CPU cores means more RAM. -ThrottleLimit has diminishing returns anyway
		$getSongsDownloadURLJob = 0..($sULength - 1) | Where-Object { $songsURL[$_].Contains('downloads.khinsider.com/game-soundtracks/album/') } | ForEach-Object -AsJob -ThrottleLimit ([Environment]::ProcessorCount * 5) -Parallel {
			$songsURL = $Using:songsURL # No need for thread safe array since each runspace only modifiy their index
			$songPageURL = $songsURL[$_]

			try {
				$SongPage = (Invoke-WebRequest -ErrorAction Stop $songPageURL).Content
			} catch {
				throw $_
			}
			$songPageHtml = New-Object -Com 'HTMLFile'
			$songPageHtml.write([System.Text.Encoding]::Unicode.GetBytes($SongPage))
			$songDownloadLinks = $songPageHtml.GetElementsByClassName('songDownloadLink')

			# Check if format is available (the format may not be available for every song)
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.innerText.EndsWith($Using:Format)) {
					$songsURL[$_] = $songDownloadLink.parentElement.href
					return
				}
			}

			# Fallback to MP3
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.innerText.EndsWith('MP3')) {
					$href = $songDownloadLink.parentElement.href
					$songsURL[$_] = $href
					# Prettify filename without extension from URL for warning
					$filename = [uri]::UnescapeDataString(((Split-Path -LeafBase $href) -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '))
					Write-Warning "${Using:albumName}: Format $Using:Format not found for $filename, fallbacking to MP3"
				}
			}
		}
		$remainingChildJobs = $getSongsDownloadURLJob.ChildJobs
		$totalCount = $remainingChildJobs.Count
		while ($getSongsDownloadURLJob.State -eq 'Running') {
			$remainingChildJobs | Wait-Job -Any > $null
			$getSongsDownloadURLJob | Receive-Job

			# Check for any failed job
			if ($remainingChildJobs | Where-Object -Property State -EQ -Value 'Failed' | Select-Object -First 1) {
				return
			}

			$remainingChildJobs = $remainingChildJobs | Where-Object -Property State -In -Value 'NotStarted', 'Running'
			$doneCount = $totalCount - $remainingChildJobs.Count
			Write-Progress -Activity "Downloading album $albumName" -Status "Converting each song page URL to download URL ($doneCount/$totalCount)" -PercentComplete (5 + [math]::Floor($doneCount / $totalCount * 15))
		}
	} catch {
		# Necessary to exit script on all errors, otherwise some errors (notably from Invoke-WebRequest) continue after finally
		# The catch can be removed when/if https://github.com/PowerShell/PowerShell/issues/21345 is fixed
		throw $_
	}
	# Save current progress even on errors or Ctrl-C
	finally {
		# Script may have interrupted before creating the job
		if ($getSongsDownloadURLJob) {
			$getSongsDownloadURLJob | Stop-Job
		} else {
			$totalCount = 1 # Avoids a division by zero
		}
		Write-Progress -Activity "Downloading album $albumName" -Status 'Saving converted URLs' -PercentComplete (5 + [math]::Floor($doneCount / $totalCount * 15))
		$tempFileTemp = "$tempFile.tmp"
		New-Item -ItemType File -Force $tempFileTemp > $null
		# $songURL can either be a download URL, or a remaining page URL if the script was interrupted
		foreach ($songURL in $songsURL) {
			Add-Content -LiteralPath $tempFileTemp -Value $songURL
		}
		Move-Item -Force -LiteralPath $tempFileTemp -Destination $tempFile
	}
} elseif ($Format -ne 'MP3') {
	Write-Warning "${albumName}: All songs URL are present, format $Format will not be checked"
}

## PREPARE FILENAMES FROM SONGS URL
$sULength = $songsURL.Length
$songsFile = [string[]]::new($sULength)
for ($index = 0; $index -lt $sULength; $index++) {
	$songDownloadURL = $songsURL[$index]
	$filename = [uri]::UnescapeDataString(((Split-Path -Leaf $songDownloadURL) -replace "[$([System.IO.Path]::GetInvalidFileNameChars() -join '') ]+", ' '))
	$filepath = Join-Path $pwd $albumName $filename
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
	Write-Progress -Activity "Downloading album $albumName" -Status "Downloading each song ($index/$sULength)" -PercentComplete (20 + [math]::Floor($index / $sULength * 80))

	$songDownloadURL = $songsURL[$index]
	$songFile = $songsFile[$index]
	try {
		Invoke-WebRequest -Resume -ErrorAction Stop -OutFile $songFile $songDownloadURL > $null
	} catch {
		# Necessary to exit on Invoke-WebRequest error, otherwise those errors don't end the script
		# The try-catch can be removed (keep only the Invoke-WebRequest command) when/if https://github.com/PowerShell/PowerShell/issues/21345 is fixed
		throw $_
	}
}

## DOWNLOADING ALBUM COVER ART
if (-not $NoCoverArt) {
	Write-Progress -Activity "Downloading album $albumName" -Status 'Downloading album cover art' -PercentComplete 99

	# Use first cover art found
	# Will silently fail (coverArtUrl set to null) if no cover art was found, although they seem to always have at least one
	$coverArtUrl = $MainPageHtml.GetElementsByClassName('albumImage')[0].GetElementsByTagName('a')[0].href
	if ($coverArtUrl) {
		$fileExtension = Split-Path -Extension $coverArtUrl
		if (-not $fileExtension) {
			Write-Warning "${albumName}: Album cover art does not have a file extension, defaulting to .jpg"
			$fileExtension = '.jpg'
		}

		$filename = 'cover' + $fileExtension
		$coverArtFile = Join-Path $pwd $albumName $filename
		Invoke-WebRequest -Resume -ErrorAction Stop -OutFile $coverArtFile $coverArtUrl > $null
	}
}

## CLEAN-UP
Remove-Item -LiteralPath $mainPageFile, $tempFile
# [System.Environment]::UserInteractive is false if there is no user interface on Windows, always true on other OSs
if ([System.Environment]::UserInteractive -and $ProgressPreference -notin 'SilentlyContinue', 'Ignore') {
	# Add a delay to show 100% complete bar for better UX
	# Write-Progress only update every 200ms and does not update to the last "missed" Write-Progress even after 200ms
	Start-Sleep -Milliseconds 200
	Write-Progress -Activity "Downloading album $albumName" -Status 'Done!' -PercentComplete 100
	Start-Sleep 1
}
Write-Progress -Completed
