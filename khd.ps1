# SPDX-License-Identifier: MPL-2.0
# Original author and source code: https://github.com/Mahtwo/KHDownloader

#region Header
# Help needs a blank before and after to be parsed

<#PSScriptInfo
.VERSION 0.0.0-placeholder

.GUID e6a05bc7-7650-4f36-8745-409565470730

.AUTHOR Mahtwo

.TAGS
Music Download CrossPlatform PSEdition_Core Windows Linux MacOS

.LICENSEURI
https://mozilla.org/MPL/2.0/

.PROJECTURI
https://github.com/Mahtwo/KHDownloader

.RELEASENOTES
https://github.com/Mahtwo/KHDownloader/releases/0.0.0-placeholder
#>

<#
.SYNOPSIS
Downloads albums from KHInsider Video Game Music with robust resume functionality.

.DESCRIPTION
The khd.ps1 script downloads albums from the KHInsider Video Game Music website.
If the script stops for any reason, it will resume when run again with the same album.

.PARAMETER Url
URL of the KHInsider album to download,
like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album.

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
& ./khd.ps1 'https://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017' m4a

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

.EXAMPLE
do {
	$loop = $false
	try {
		& ./khd.ps1 'https://downloads.khinsider.com/game-soundtracks/album/the-legend-of-zelda-breath-of-the-wild' flac
	}
	# Will still throw on other errors (for example parameters errors)
	catch [System.Net.Http.HttpRequestException] {
		$loop = $true
	}
} while ($loop)

.LINK
KHInsider home page : https://downloads.khinsider.com

.LINK
https://github.com/Mahtwo/KHDownloader
#>

#Requires -PSEdition Core
# Suppress some PSScript-Analyzer warnings
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'commandAst', Justification = 'variable not used in ArgumentCompleter of formats')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'commandName', Justification = 'variable not used in ArgumentCompleter of formats')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'parameterName', Justification = 'variable not used in ArgumentCompleter of formats')]
# TODO : Only get songs page URL from the last downloaded song to last song of the album (since it may be partially downloaded). That means only last song if album is fully downloaded
#endregion Header

#region Parameters
param (
	[Parameter(Position = 0, Mandatory, HelpMessage = 'URL of the album to download, like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album')]
	[Alias('u', 'Uri')]
	[ValidateScript({
			if ($_ -notmatch '^(https?://)?downloads.khinsider.com/game-soundtracks/album/[^/]+$') {
				throw 'Invalid URL, it should look like https://downloads.khinsider.com/game-soundtracks/album/name-of-the-album'
			}

			if ($null -eq $_.Scheme) {
				[uri]$url = "https://$_"
			} else {
				[uri]$url = $_
			}

			# Check internet by trying to connect to the URL
			if (-not (Test-Connection $url.Host -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
				throw "$($url.Host) is unreachable, check your internet connection."
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($url.Segments[-1] + '.html')
			# Skip check if main page HTML file already exist
			if (Test-Path -PathType Leaf $mainPageFile) {
				return $true
			}


			# The file will only be created after downlading it entirely
			$mainPage = (Invoke-WebRequest -PassThru -ErrorAction Stop -OutFile $mainPageFile $url).Content
			# Check if the URL is a valid album URL
			if ($mainPage -match '<title>\s*Error\s*<\/title>') {
				Remove-Item -LiteralPath $mainPageFile
				throw "The album $_ does not exist"
			}

			return $true
		}
	)]
	[uri]$Url,

	[Parameter(Position = 1, HelpMessage = 'Format to prioritize (FLAC, M4A, etc.), default/fallback is MP3. Can TAB complete based on -Url')]
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
				[uri]$url = $fakeBoundParameters['Url']
			} else {
				[uri]$url = "https://$($fakeBoundParameters['Url'])"
			}

			$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($url.Segments[-1] + '.html')
			if (Test-Path -PathType Leaf $mainPageFile) {
				$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
			} else {
				# Will silently fail if no internet connection (which is what we want)
				$mainPage = (Invoke-WebRequest -PassThru -ErrorAction Stop -OutFile $mainPageFile $url).Content
			}
			# Check if the URL is a valid album URL
			if ($mainPage -match '<title>\s*Error\s*<\/title>') {
				return
			}

			# SingleLine makes . match new line characters, [\s\S] would work with -replace but it's more cumbersome
			# .*? does the shortest match while .* does the biggest match
			# Get entire tr of songlist_header
			$tableHeader = [regex]::Replace($mainPage, '.*(<tr[^>]*songlist_header.*?</tr>).*', '$1', 'SingleLine')
			# Get each th value and remove all HTML tags
			$tableHeaderValues = [regex]::Matches($tableHeader, '<th[^>]*>(.*?)</th[^>]*>', 'SingleLine') |
				ForEach-Object { $_.Groups[1].Value -replace '<[^>]*>' }
			$availableFormats = @()
			for ($i = $tableHeaderValues.Length - 3; $tableHeaderValues[$i] -ne 'Song Name'; $i--) {
				$availableFormats += $tableHeaderValues[$i]
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

# Formatting arguments
if ($null -eq $Url.Scheme) {
	$Url = "https://$Url"
}
$Format = $Format.ToUpperInvariant() # No null check needed as a string cannot be null
#endregion Parameters

#region Helpers
function Write-ProgressHelper {
	param(
		[string]$Status,
		[int]$PercentComplete,
		[switch]$Completed,
		[switch]$WaitUpdate
	)

	if ($WaitUpdate) {
		# Write-Progress only updates every 200ms and does not update to the last "missed" Write-Progress even after 200ms
		if (-not $timerWriteProgressHelper) {
			$timerWriteProgressHelper = [System.Threading.Tasks.Task]::Delay(2000)
		}
		$timerWriteProgressHelper.Wait()
	}
	$timerWriteProgressHelper = [System.Threading.Tasks.Task]::Delay(2000)
	# Cannot combine -Status $Status and -Completed:$Completed because it would throw when Status is not specified
	if ($Completed) {
		Write-Progress -Completed
	} else {
		Write-Progress -Activity "Downloading album $albumName" -Status $Status -PercentComplete $PercentComplete
	}
}
function Write-WarningHelper {
	param(
		[ValidateNotNull()]
		[string]$Message
	)
	Write-Warning "${albumName}: $Message"
}
function ConvertTo-ValidPath {
	param(
		[Parameter(ValueFromPipeline)]
		[ValidateNotNull()]
		[string]$Path
	)

	begin {
		# Removing Windows illegal characters so it's compatible between OS (Linux and macOS are subsets)
		# Some characters are technically valid like horizontal tabulation "	" but it's not important
		$illegalCharacters = ([char[]](0..31) + [char[]]':*?"<>|') -join ''
	}
	process {
		# Replace consecutive illegal characters and whitespaces with a single space...
		# ...Trim whitespace characters at the beginning and whitespace + dot "." characters at the end
		return ($Path -replace "[$illegalCharacters\s]+", ' ') -replace '^\s*|[\s\.]*$'
	}
}
#endregion Helpers

#region Get album name
# Main page HTML file already exist because of argument URL ValidateScript
$mainPageFile = Join-Path ([System.IO.Path]::GetTempPath()) ($Url.Segments[-1] + '.html')
$mainPage = Get-Content -Raw -LiteralPath $mainPageFile
# Get first h2, replace illegal path characters and consecutive spaces to one space
$albumName = ([regex]::Match($mainPage, '<h2[^>]*>(.*?)</h2[^>]*>')).Groups[1] | ConvertTo-ValidPath
#endregion Get album name

#region Get songs page URL
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ($Url.Segments[-1] + '.khd')
if (-not (Test-Path -PathType Leaf $tempFile)) {
	Write-ProgressHelper -Status 'Getting each song page URL' -PercentComplete 0

	# Get page URL of each song
	# Get from playlistDownloadSong to shortest href and capture href content
	$songsPageURL = [regex]::Matches($mainPage, 'playlistDownloadSong.*?href="([^"]*)"', 'SingleLine') |
		ForEach-Object { $_.Groups[1].Value }
	$pDSLength = $songsPageURL.Length
	$songsURL = [string[]]::new($pDSLength)
	# Fast enough, parallelization would be slower
	for ($index = 0; $index -lt $pDSLength; $index++) {
		Write-ProgressHelper -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete ([System.Math]::Floor($index / $pDSLength * 5))
		$songsURL[$index] = $Url.GetLeftPart([System.UriPartial]::Authority) + $songsPageURL[$index]
	}

	# Create file containing all songs page URLs
	# There is a weird bug with Add-Content -LiteralPath (but not -Path or Out-File -LiteralPath) where
	# 	if the path points to a file that does not exist AND the path use a PSDrive with a root that does not end with
	# 	a trailing path separator (which is the case with Pester TestDrive), Add-Content does not create the file
	New-Item -Path $tempFile -ItemType File > $null
	Add-Content -LiteralPath $tempFile -Value $songsURL

	Write-ProgressHelper -Status "Getting each song page URL ($index/$pDSLength)" -PercentComplete 5
} else {
	$songsURL = Get-Content -LiteralPath $tempFile
}
#endregion Get songs page URL

#region Get songs download URL
if (($songsURL -join '').Contains('downloads.khinsider.com/game-soundtracks/album/')) {
	Write-ProgressHelper -Status 'Converting each song page URL to download URL' -PercentComplete 5

	if ($Format -ne 'MP3') {
		# Check if the format is available for this album
		$formatAvailable = $false
		# Get entire tr of songlist_header
		$tableHeader = [regex]::Replace($mainPage, '.*(<tr[^>]*songlist_header.*?</tr>).*', '$1', 'SingleLine')
		# Get each th value and remove all HTML tags
		$tableHeaderValues = [regex]::Matches($tableHeader, '<th[^>]*>(.*?)</th[^>]*>', 'SingleLine') |
			ForEach-Object { $_.Groups[1].Value -replace '<[^>]*>' }
		for ($i = $tableHeaderValues.Length - 3; $tableHeaderValues[$i] -ne 'Song Name'; $i--) {
			if ($tableHeaderValues[$i] -eq $Format) {
				$formatAvailable = $true
				break
			}
		}
		if (-not $formatAvailable) {
			Write-WarningHelper "Format $Format not available, fallbacking to MP3"
			$Format = 'MP3'
		}
	}

	$sULength = $songsURL.Length
	try {
		# Put helper functions in variable to use them inside the job ($Using:Function:... does not work)
		$jobFunctions = Get-ChildItem -Path Function: | Where-Object Name -In Write-WarningHelper, ConvertTo-ValidPath |
			Select-Object -Property Name, Definition

		# We assume more CPU cores means more RAM too. -ThrottleLimit has diminishing returns anyway
		# editorconfig-checker-disable-next-line because splitting by pipeline adds an indentation and the closing brace } isn't aligned
		$getSongsDownloadURLJob = 0..($sULength - 1) | Where-Object { $songsURL[$_].Contains('downloads.khinsider.com/game-soundtracks/album/') } | ForEach-Object -AsJob -ThrottleLimit ([System.Environment]::ProcessorCount * 5) -Parallel {
			#region Get songs download URL - Job
			#region Get songs download URL - Job setup
			$songsURL = $Using:songsURL # No need for thread safe array since each runspace only modifiy their index
			$albumName = $Using:albumName # Used by Write-WarningHelper
			$Format = $Using:Format
			foreach ($jobFunction in $Using:jobFunctions) {
				New-Item -Path Function: -Name $jobFunction.Name -Value $jobFunction.Definition > $null
			}
			#endregion Get songs download URL - Job setup

			$songPageURL = $songsURL[$_]
			try {
				$SongPage = (Invoke-WebRequest -ErrorAction Stop $songPageURL).Content
			} catch {
				throw $_
			}
			# Matches : Get from href to shortest songDownloadLink (without encountering another href) to shortest </span>
			$songDownloadLinks = [regex]::Matches($SongPage, 'href(?:(?!href).)*?songDownloadLink.*?</span[^>]*>', 'SingleLine') | ForEach-Object {
				[PSCustomObject]@{
					# Get href inside
					href   = [regex]::Replace($_.Value, '.*href="([^"]*)".*', '$1', 'SingleLine')
					# Get text between "download as " and "<"
					Format = [regex]::Replace($_.Value, '.*download\s*as\s*([^<]*)<.*', '$1', 'SingleLine')
				}
			}

			# Check if format is available (the format may not be available for every song)
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.Format -eq $Format) {
					$songsURL[$_] = $songDownloadLink.href
					return
				}
			}

			# Fallback to MP3
			foreach ($songDownloadLink in $songDownloadLinks) {
				if ($songDownloadLink.Format -eq 'MP3') {
					$songsURL[$_] = $songDownloadLink.href
					# Prettify filename without extension from URL for warning
					$filename = [uri]::UnescapeDataString(((Split-Path -LeafBase $songDownloadLink.href) | ConvertTo-ValidPath))
					Write-WarningHelper "Format $Format not found for $filename, fallbacking to MP3"
				}
			}
			#endregion Get songs download URL - Job
		}
		$remainingChildJobs = $getSongsDownloadURLJob.ChildJobs
		$totalCount = $remainingChildJobs.Count
		while ($getSongsDownloadURLJob.State -eq 'Running') {
			$remainingChildJobs | Wait-Job -Any > $null
			$getSongsDownloadURLJob | Receive-Job

			# Check for any failed job
			if ($remainingChildJobs | Where-Object State -EQ 'Failed' | Select-Object -First 1) {
				return
			}

			$remainingChildJobs = $remainingChildJobs | Where-Object State -In 'NotStarted', 'Running'
			$doneCount = $totalCount - $remainingChildJobs.Count
			Write-ProgressHelper -Status "Converting each song page URL to download URL ($doneCount/$totalCount)" -PercentComplete (5 + [System.Math]::Floor($doneCount / $totalCount * 15))
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
			$getSongsDownloadURLJob | Stop-Job -PassThru | Receive-Job -AutoRemoveJob -Wait
		}
		if (-not $totalCount) {
			$totalCount = 1 # Avoids a division by zero
		}
		Write-ProgressHelper -Status 'Saving converted URLs' -PercentComplete (5 + [System.Math]::Floor($doneCount / $totalCount * 15))
		$tempFileTemp = "$tempFile.tmp"
		New-Item -ItemType File -Force $tempFileTemp > $null
		# $songsURL may have a mix of download URLs and page URLs if the script was interrupted
		Add-Content -LiteralPath $tempFileTemp -Value $songsURL
		Move-Item -Force -LiteralPath $tempFileTemp -Destination $tempFile
	}
} elseif ($Format -ne 'MP3') {
	Write-WarningHelper "All songs URL are present, format $Format will not be checked"
}
#endregion Get songs download URL

#region Prepare filenames
$sULength = $songsURL.Length
$songsFile = [string[]]::new($sULength)
$albumDirectory = Join-Path $PWD $albumName
for ($index = 0; $index -lt $sULength; $index++) {
	$songDownloadURL = $songsURL[$index]
	$filename = [uri]::UnescapeDataString(((Split-Path -Leaf $songDownloadURL) | ConvertTo-ValidPath))
	$filepath = Join-Path $albumDirectory $filename
	$songsFile[$index] = $filepath
}
#endregion Prepare filenames

#region Download songs
if (-not (Test-Path -PathType Container $albumDirectory)) {
	New-Item -ItemType Directory $albumDirectory > $null
}
for ($index = 0; $index -lt $sULength; $index++) {
	# Skip to the last downloaded file as it may only be partially downloaded
	if ($index + 1 -ne $sULength -and (Test-Path -PathType Leaf $songsFile[$index + 1])) {
		continue
	}
	Write-ProgressHelper -Status "Downloading each song ($index/$sULength)" -PercentComplete (20 + [System.Math]::Floor($index / $sULength * 80))

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
#endregion Download songs

#region Download cover art
if (-not $NoCoverArt) {
	Write-ProgressHelper -Status 'Downloading album cover art' -PercentComplete 99

	# Use first cover art found
	# Will silently fail (coverArtUrl set to empty string) if no cover art was found, although they seem to always have at least one
	# Get entire div of first albumImage (Match only gets first unlike Matches)
	$albumImageFirst = ([regex]::Match($mainPage, '<div[^>]*albumImage[^>]*>.*?</div>', 'SingleLine')).Value
	# Get href inside
	$coverArtUrl = [regex]::Replace($albumImageFirst, '.*href="([^"]*)".*', '$1', 'SingleLine')
	if ($coverArtUrl) {
		$fileExtension = Split-Path -Extension $coverArtUrl
		if (-not $fileExtension) {
			Write-WarningHelper 'Album cover art does not have a file extension, defaulting to .jpg'
			$fileExtension = '.jpg'
		}

		$filename = 'cover' + $fileExtension
		$coverArtFile = Join-Path $albumDirectory $filename
		Invoke-WebRequest -Resume -ErrorAction Stop -OutFile $coverArtFile $coverArtUrl > $null
	} else {
		Write-WarningHelper 'No album cover art found'
	}
}
#endregion Download cover art

#region Clean-up
Remove-Item -LiteralPath $mainPageFile, $tempFile
# [System.Environment]::UserInteractive is false if there is no user interface on Windows, always true on other OSs
if ([System.Environment]::UserInteractive -and $ProgressPreference -notin 'SilentlyContinue', 'Ignore') {
	Write-ProgressHelper -Status 'Done!' -PercentComplete 100 -WaitUpdate
	# Add a delay to show 100% complete bar for better UX
	Start-Sleep 1
}
Write-ProgressHelper -Completed
#endregion Clean-up
