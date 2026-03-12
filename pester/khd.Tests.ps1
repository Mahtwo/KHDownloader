#region Header
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Does not work with (Pester) script blocks')]
param() # Necessary for the PSScriptAnalyzer suppress rules above
#endregion Header

#region Setup
BeforeAll {
	$writeDebugMock = $____Pester.Configuration.Output.Verbosity.Value -eq 'Diagnostic' -or $____Pester.Configuration.Debug.WriteDebugMessages.Value -or $DebugPreference -in 'Inquire', 'Continue'
	$cmdlets = @{}
	foreach ($cmdlet in 'Invoke-WebRequest', 'Test-Connection', 'New-Item', 'Move-Item', 'Remove-Item', 'Add-Content', 'Join-Path', 'ForEach-Object') {
		$cmdlets.Add($cmdlet, (Get-Command -CommandType Cmdlet -Name $cmdlet))
	}
	$khdFile = & $cmdlets['Join-Path'] (Split-Path -Parent $PSScriptRoot) 'khd.ps1'
	$albumUrl = 'https://downloads.khinsider.com/game-soundtracks/album/powershell-and-pester-racing-original-soundtrack'
	$_ProgressPreference = $ProgressPreference
	$ProgressPreference = 'SilentlyContinue'
	$_ErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = 'Stop'

	#region Setup - Mocks
	# Mock internet access to local file system
	Mock Invoke-WebRequest {
		$path = & $cmdlets['Join-Path'] $PSScriptRoot 'web' $Uri.Host $Uri.AbsolutePath
		if (-not (Split-Path -Extension $path)) {
			$path = & $cmdlets['Join-Path'] $path 'index.html'
		}
		Write-Debug -Debug:$writeDebugMock -Message "Invoke-WebRequest: `"$Uri`" --> `"$path`""
		if ($OutFile) {
			if (-not (Test-InTestDrive $OutFile)) {
				throw 'Invoke-WebRequest must not output files outside of TestDrive'
			}
			Copy-Item -LiteralPath $path -Destination $OutFile
		}
		if (($OutFile -and $PassThru) -or -not $OutFile) {
			# Content will only work with text files
			# It's troublesome (and useless in our case) to have something that works with both text files and binary files
			return @{ Content = (Get-Content -Raw -LiteralPath $path) }
		}
	}
	Mock Test-Connection { return $true }

	# Mock file modifications to TestDrive
	function Test-InTestDrive {
		param([string[]]$Paths)

		# Return false if any path is not in test drive
		foreach ($Path in $Paths) {
			if (-not $Path) { continue }
			# If path is not absolute (is relative)
			# IsPathRooted does not detect TestDrive:
			if (-not [System.IO.Path]::IsPathRooted($Path) -and -not $Path.StartsWith('TestDrive:')) {
				# Applies relative path . and ..
				$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((& $cmdlets['Join-Path'] $PWD $Path))
			}
			if (-not $Path.StartsWith('TestDrive:') -and -not $Path.StartsWith($TestDrive)) {
				return $false
			}
		}
		return $true
	}
	Mock New-Item -ParameterFilter {
		if ($Path -and $Name) {
			return -not (Test-InTestDrive (& $cmdlets['Join-Path'] $Path $Name))
		}
		return -not (Test-InTestDrive $Path, $Name)
	} -MockWith {
		throw 'New-Item must not create items outside of TestDrive'
	}
	Mock Move-Item -ParameterFilter { -not (Test-InTestDrive $Path, $LiteralPath, $Destination) } -MockWith {
		throw 'Remove-Item must not remove items outside of TestDrive'
	}
	Mock Remove-Item -ParameterFilter { -not (Test-InTestDrive $Path, $LiteralPath) } -MockWith {
		throw 'Remove-Item must not remove items outside of TestDrive'
	}
	Mock Add-Content -ParameterFilter { -not (Test-InTestDrive $Path, $LiteralPath) } -MockWith {
		throw 'Add-Content must not add content outside of TestDrive'
	}
	# Change temp directory and working directory to TestDrive
	Mock Join-Path -ParameterFilter {
		if ($PesterBoundParameters.ContainsKey('Path') -and $PesterBoundParameters.ContainsKey('PSPath')) {
			$PesterBoundParameters.Remove('PSPath')
		}
		$originalResult = & $cmdlets['Join-Path'] @PesterBoundParameters
		return -not (Test-InTestDrive $originalResult)
	} -MockWith {
		$originalResult = & $cmdlets['Join-Path'] @PesterBoundParameters
		$tempPath = [System.IO.Path]::GetTempPath()
		switch -Wildcard ($originalResult) {
			"$tempPath*" {
				$newResult = & $cmdlets['Join-Path'] 'TestDrive:' ($_ -replace "^$([Regex]::Escape($tempPath))")
				break
			}
			"$PWD*" {
				$newResult = & $cmdlets['Join-Path'] 'TestDrive:' ($_ -replace "^$([Regex]::Escape($PWD))")
				break
			}
			default { throw 'Join-Path result not in valid directories' }
		}
		Write-Debug -Debug:$writeDebugMock -Message "Join-Path: `"$originalResult`" --> `"$newResult`""
		return $newResult
	}

	# Jobs runs in new sessions which means they don't keep mocks from parent
	# The Mock cmdlet does not work outside of Pester
	# We must reimplement mocks inside the script blocks executed by jobs
	Mock ForEach-Object -ParameterFilter { $Parallel -and $AsJob } -MockWith {
		$mocks = {
			function Invoke-WebRequest {
				param(
					[Parameter(Position = 0, Mandatory)] # Automatically adds ErrorAction, Verbose, etc. parameters
					[uri]$Uri
				)
				# $args only contain remaining arguments not handled by parameters, so it should be empty
				if ($args) {
					throw 'Invoke-WebRequest called with unexpected arguments. If expected, change Mock accordingly'
				}

				$path = Join-Path $Using:PSScriptRoot 'web' $Uri.Host $Uri.AbsolutePath
				if (-not (Split-Path -Extension $path)) {
					$path = Join-Path $path 'index.html'
				}
				Write-Debug -Debug:$Using:writeDebugMock -Message "Invoke-WebRequest: `"$Uri`" --> `"$path`""
				return @{ Content = (Get-Content -Raw -LiteralPath $path) }
			}
		}
		$PesterBoundParameters.Parallel = [scriptblock]::Create($mocks.ToString() + $Parallel.ToString())
		# When mocking ForEach-Object, it will process piped inputs one by one instead of all at once which means
		# 	the ForEach-Object -AsJob -Parallel will return per input a job with one child job
		# However that luckily doesn't cause any problems since PowerShell will simply merge all when calling
		# 	properties like .ChildJobs and ".State -eq 'Running'" returns a collection which will be false when empty
		# If it ever becomes necessary to fix this, it might be necessary to mock the Where-Object
		return & $cmdlets['ForEach-Object'] @PesterBoundParameters
	}
	#endregion Setup - Mocks
}
AfterAll {
	$ProgressPreference = $_ProgressPreference
	$ErrorActionPreference = $_ErrorActionPreference
}
#endregion Setup

Describe 'khd.ps1' {
	#region Parameters validation
	Context 'Parameters validation' {
		BeforeAll {
			# Mocking keeps the param() block while removing rest of code, which is useful for testing parameters
			# We put the entire script content in a function because scripts cannot be mocked directly
			Set-Item -Path Function:khd -Value (Get-Content -Raw $khdFile)
			Mock khd {}

			Mock Invoke-WebRequest { return @{ Content = '' } }
		}

		It 'All parameters should be correctly exposed' {
			Get-Command $khdFile | Should -HaveParameter Url -Type uri -Mandatory
			Get-Command $khdFile | Should -HaveParameter Format -Type string -DefaultValue MP3 -HasArgumentCompleter
			# -Not applies on the entire Should, we cannot verify type AND not mandatory in one command
			Get-Command $khdFile | Should -Not -HaveParameter Format -Mandatory
			Get-Command $khdFile | Should -HaveParameter NoCoverArt -Type switch
			Get-Command $khdFile | Should -Not -HaveParameter NoCoverArt -Mandatory
		}

		It 'Invalid URL should throw an invalid URL error' {
			{ & khd 'https://this.com/is/an/invalid/url' } | Should -Throw '*Invalid URL*'
			{ & khd 'https://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017/' } | Should -Throw '*Invalid URL*' -Because 'trailing slash is invalid'
			# Should -Not -Throw does not actually use ExpectedMessage and instead fails on any throw (Should -Throw does use it)
			# Keep ExpectedMessage anyway in case this is changed
			{ & khd 'downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017' } | Should -Not -Throw '*Invalid URL*' -Because 'http(s):// can be omitted'
			{ & khd 'http://downloads.khinsider.com/game-soundtracks/album/malicious-fallen-original-soundtrack-2017' } | Should -Not -Throw '*Invalid URL*' -Because 'http:// is also allowed'
		}

		It 'No internet should throw an internet connection error' {
			Mock Test-Connection { return $false } # Simulates no internet
			{ & khd -Url $albumUrl } | Should -Throw '*unreachable*internet*'
		}

		It 'No album should throw an album does not exist error' {
			$noSuchAlbumHTML = Get-Content -Raw (& $cmdlets['Join-Path'] $PSScriptRoot 'web' 'error no album.html')
			Mock Invoke-WebRequest { return @{ Content = $noSuchAlbumHTML } }
			Mock Remove-Item {}
			{ & khd -Url $albumUrl } | Should -Throw '*album*does not exist*'
		}
	}
	#endregion Parameters validation

	#region Script execution
	Context 'Script execution' {
		#region Script execution - Setup
		BeforeAll {
			$downloadAlbumDirectory = Join-Path 'TestDrive:' 'PowerShell & Pester Racing Original Soundtrack'
			$sourceDirectory = & $cmdlets['Join-Path'] $PSScriptRoot 'web' 'lambda.vgmtreasurechest.com' 'soundtracks' 'powershell-and-pester-racing-original-soundtrack'
			$sourceCoverFile = Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.png'
			$sourceMp3Files = Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.mp3' -Depth 1
			$sourceM4aFile = Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.m4a' -Depth 1
			$sourceMp3ExclusiveFiles = $sourceMp3Files | Where-Object -Property BaseName -NotLike -Value $sourceM4aFile.BaseName
			$Script:testIndex = 0

			function Test-DownloadedFilesHash {
				param([string[]]$SourceFiles)

				$downloadedFiles = Get-ChildItem -LiteralPath $downloadAlbumDirectory
				$downloadedFiles | Should -HaveCount $SourceFiles.Count
				$sourceHashes = Get-FileHash -LiteralPath $SourceFiles
				foreach ($downloadedFile in $downloadedFiles) {
					(Get-FileHash -LiteralPath $downloadedFile).Hash | Should -BeIn $sourceHashes.Hash
				}
			}
		}
		# TestDrive is per Describe/Context, not per test (It), so we modify TestDrive (drive and variable) before each test
		BeforeEach {
			$_testDrivePSDrive = Get-PSDrive -Name TestDrive -PSProvider FileSystem -Scope Global
			$_testDrivePSDrive | Remove-PSDrive
			$TestDrive = & $cmdlets['Join-Path'] $_testDrivePSDrive.Root "test_$testIndex"
			New-Item -Path $TestDrive -ItemType Directory > $null
			$testDrivePSDrive = New-PSDrive -Name $_testDrivePSDrive.Name -PSProvider $_testDrivePSDrive.Provider -Root $TestDrive -Scope Global -Description $_testDrivePSDrive.Description
		}
		AfterEach {
			$testDrivePSDrive | Remove-PSDrive
			$TestDrive = $_testDrivePSDrive.Root
			New-PSDrive -Name $_testDrivePSDrive.Name -PSProvider $_testDrivePSDrive.Provider -Root $TestDrive -Scope Global -Description $_testDrivePSDrive.Description > $null
			$Script:testIndex++
		}
		AfterAll {
			Remove-Variable -Name testIndex -Scope Script
		}
		#endregion Script execution - Setup

		#region Script execution - Full
		Context 'Full run' {
			It 'Standard script execution should download mp3 songs and album cover art' {
				# & $khdFile -Url $albumUrl on its own would also fail the test if throwing, but it would only
				# 	show line number in stack trace while Should -Not -Throw also show the code
				{ & $khdFile -Url $albumUrl } | Should -Not -Throw
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter 'cover.*' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.mp3' | Should -HaveCount 3
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 4
				Test-DownloadedFilesHash (@($sourceCoverFile) + @($sourceMp3Files))
			}

			It 'Format parameter should be applied case-insensitively with fallback to mp3 per song' {
				{ & $khdFile -Url $albumUrl -Format m4A -WarningAction SilentlyContinue -WarningVariable script:warningOutput } | Should -Not -Throw
				$warningOutput | Where-Object -Property Message -Like -Value '*Format*MP3*' | Should -HaveCount 2 -Because 'two songs are only available in MP3'
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter 'cover.*' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.mp3' | Should -HaveCount 2
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.m4a' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 4
				Test-DownloadedFilesHash (@($sourceCoverFile) + @($sourceM4aFile) + @($sourceMp3ExclusiveFiles))
			}

			It 'Unavailable Format parameter for whole album should display only one format not available warning and fallback to mp3' {
				{ & $khdFile -Url $albumUrl -Format FLAC -WarningAction SilentlyContinue -WarningVariable script:warningOutput } | Should -Not -Throw
				$warningOutput | Where-Object -Property Message -Like -Value '*Format*MP3*' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter 'cover.*' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.mp3' | Should -HaveCount 3
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 4
				Test-DownloadedFilesHash (@($sourceCoverFile) + @($sourceMp3Files))
			}

			It 'NoCoverArt parameter should still download songs but not album cover art' {
				{ & $khdFile -Url $albumUrl -NoCoverArt } | Should -Not -Throw
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter 'cover.*' | Should -BeNullOrEmpty
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 3
				Test-DownloadedFilesHash $sourceMp3Files
			}
		}
		#endregion Script execution - Full

		#region Script execution - Resume
		Context 'Resume run' {
			BeforeAll {
				$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) 'powershell-and-pester-racing-original-soundtrack.khd'
				function Set-TempFile {
					[CmdletBinding(SupportsShouldProcess)]
					param(
						[Parameter(Position = 0, Mandatory)]
						[ValidateSet('SongsPageURL', 'SongsURL', 'Mix')]
						[string]$type
					)

					$content = switch ($type) {
						'SongsPageURL' {
							@(
								'https://downloads.khinsider.com/game-soundtracks/album/powershell-and-pester-racing-original-soundtrack/01.%2520Title%2520Screen.mp3'
								'https://downloads.khinsider.com/game-soundtracks/album/powershell-and-pester-racing-original-soundtrack/02.%2520Main%2520Menu.mp3'
								'https://downloads.khinsider.com/game-soundtracks/album/powershell-and-pester-racing-original-soundtrack/03.%2520Credits.mp3'
								''
							) -join [System.Environment]::NewLine
						}
						'Mix' {
							@(
								'https://lambda.vgmtreasurechest.com/soundtracks/powershell-and-pester-racing-original-soundtrack/bbbeqpez/01.%20Title%20Screen.mp3'
								'https://downloads.khinsider.com/game-soundtracks/album/powershell-and-pester-racing-original-soundtrack/02.%2520Main%2520Menu.mp3'
								'https://lambda.vgmtreasurechest.com/soundtracks/powershell-and-pester-racing-original-soundtrack/gphqgjdn/03.%20Credits.mp3'
								''
							) -join [System.Environment]::NewLine
						}
						'SongsURL' {
							@(
								'https://lambda.vgmtreasurechest.com/soundtracks/powershell-and-pester-racing-original-soundtrack/bbbeqpez/01.%20Title%20Screen.mp3'
								'https://lambda.vgmtreasurechest.com/soundtracks/powershell-and-pester-racing-original-soundtrack/zahgmppf/02.%20Main%20Menu.mp3'
								'https://lambda.vgmtreasurechest.com/soundtracks/powershell-and-pester-racing-original-soundtrack/gphqgjdn/03.%20Credits.mp3'
								''
							) -join [System.Environment]::NewLine
						}
					}
					New-Item -Path $tempFile -ItemType File -Force -Value $content > $null
				}
			}

			It 'Songs page URL in temp file should skip parsing songs page URL from HTML again' {
				Set-TempFile 'SongsPageURL'
				Mock New-Item -Verifiable -ParameterFilter { $LiteralPath -like '*.khd' -or $Path -like '*.khd' }
				{ & $khdFile -Url $albumUrl -NoCoverArt } | Should -Not -Throw
				Should -Not -InvokeVerifiable
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter 'cover.*' | Should -BeNullOrEmpty
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 3
				Test-DownloadedFilesHash $sourceMp3Files
			}

			It 'A mix of songs page URL and songs URL should only execute jobs on remaining songs page URL' {
				Set-TempFile 'Mix'
				{ & $khdFile -Url $albumUrl -Format M4A -NoCoverArt } | Should -Not -Throw
				# When mocked, ForEach-Object is called once per input
				Should -Invoke ForEach-Object -Times 1 -Exactly -Because 'there is only one remaining song page URL'
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.mp3' | Should -HaveCount 2
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.m4a' | Should -HaveCount 1
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 3
				Test-DownloadedFilesHash (@($sourceM4aFile) + @($sourceMp3ExclusiveFiles))
			}

			It 'Format parameter when songs URL are already present should display a format not checked warning' {
				Set-TempFile 'SongsURL'
				{ & $khdFile -Url $albumUrl -Format M4A -NoCoverArt -WarningAction SilentlyContinue -WarningVariable script:warningOutput } | Should -Not -Throw
				$warningOutput | Where-Object -Property Message -Like -Value '*format*not*checked*' | Should -Not -BeNullOrEmpty
				Get-ChildItem -LiteralPath $downloadAlbumDirectory -Filter '*.mp3' | Should -HaveCount 3
				Get-ChildItem -LiteralPath $downloadAlbumDirectory | Should -HaveCount 3
				Test-DownloadedFilesHash $sourceMp3Files
			}
		}
		#endregion Script execution - Resume
	}
	#endregion Script execution
}
