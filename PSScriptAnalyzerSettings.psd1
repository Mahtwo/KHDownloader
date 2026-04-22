@{
	IncludeRules = @(
		'PSAlignAssignmentStatement',
		'PSAvoidAssignmentToAutomaticVariable',
		'PSAvoidDefaultValueForMandatoryParameter',
		'PSAvoidDefaultValueSwitchParameter',
		'PSAvoidExclaimOperator',
		'PSAvoidGlobalAliases',
		'PSAvoidGlobalFunctions',
		'PSAvoidGlobalVars',
		'PSAvoidInvokingEmptyMembers',
		'PSAvoidMultipleTypeAttributes',
		'PSAvoidNullOrEmptyHelpMessageAttribute',
		'PSAvoidReservedWordsAsFunctionNames',
		'PSAvoidSemicolonsAsLineTerminators',
		'PSAvoidShouldContinueWithoutForce',
		'PSAvoidTrailingWhitespace',
		'PSAvoidUsingAllowUnencryptedAuthentication',
		'PSAvoidUsingBrokenHashAlgorithms',
		'PSAvoidUsingCmdletAliases',
		'PSAvoidUsingComputerNameHardcoded',
		'PSAvoidUsingConvertToSecureStringWithPlainText',
		'PSAvoidUsingDeprecatedManifestFields',
		'PSAvoidUsingDoubleQuotesForConstantString',
		'PSAvoidUsingEmptyCatchBlock',
		'PSAvoidUsingInvokeExpression',
		'PSAvoidUsingPlainTextForPassword',
		'PSAvoidUsingPositionalParameters',
		'PSAvoidUsingUsernameAndPasswordParams',
		'PSAvoidUsingWMICmdlet',
		'PSAvoidUsingWriteHost',
		'PSMisleadingBacktick',
		'PSMissingModuleManifestField',
		'PSPlaceCloseBrace',
		'PSPlaceOpenBrace',
		'PSPossibleIncorrectComparisonWithNull',
		'PSPossibleIncorrectUsageOfAssignmentOperator',
		'PSPossibleIncorrectUsageOfRedirectionOperator',
		'PSProvideCommentHelp',
		'PSReservedCmdletChar',
		'PSReservedParams',
		'PSReviewUnusedParameter',
		'PSShouldProcess',
		'PSUseApprovedVerbs',
		'PSUseBOMForUnicodeEncodedFile',
		'PSUseCmdletCorrectly',
		'PSUseCompatibleSyntax',
		'PSUseConsistentIndentation',
		'PSUseConsistentParameterSetName',
		'PSUseConsistentParametersKind',
		'PSUseConsistentWhitespace',
		'PSUseCorrectCasing',
		'PSUseDeclaredVarsMoreThanAssignments',
		'PSUseLiteralInitializerForHashtable',
		'PSUseOutputTypeCorrectly',
		'PSUseProcessBlockForPipelineCommand',
		'PSUsePSCredentialType',
		'PSUseShouldProcessForStateChangingFunctions',
		'PSUseSingleValueFromPipelineParameter',
		'PSUseSingularNouns',
		'PSUseSupportsShouldProcess',
		'PSUseToExportFieldsInManifest',
		'PSUseUsingScopeModifierInNewRunspaces',
		'PSUseUTF8EncodingForHelpFile'
	)

	Rules        = @{
		PSAlignAssignmentStatement       = @{
			Enable = $true
		}

		PSAvoidUsingPositionalParameters = @{
			CommandAllowList = 'Join-Path'
		}


		PSPlaceCloseBrace                = @{
			Enable       = $true
			NewLineAfter = $false # Only branch statements. "} else {" is correct, but not "} New-Item"
		}

		PSPlaceOpenBrace                 = @{
			Enable = $true
		}

		PSUseCompatibleSyntax            = @{
			Enable         = $true
			TargetVersions = @(
				'7.5.4'
			)
		}

		PSUseConsistentIndentation       = @{
			Enable = $true
			Kind   = 'tab'
		}

		PSUseConsistentParameterSetName  = @{
			Enable = $true
		}

		# https://github.com/PowerShell/PSScriptAnalyzer/blob/9b55ac29a91e6de07defa93bdf9f417b1468f66b/Tests/Rules/UseConsistentParametersKind.Tests.ps1#L9-L12
		PSUseConsistentParametersKind    = @{
			Enable         = $true
			ParametersKind = 'ParamBlock'
		}

		PSUseConsistentWhitespace        = @{
			Enable                                  = $true
			CheckPipeForRedundantWhitespace         = $true
			CheckParameter                          = $true
			IgnoreAssignmentOperatorInsideHashTable = $true
		}

		PSUseCorrectCasing               = @{
			Enable = $true
		}
	}
}
