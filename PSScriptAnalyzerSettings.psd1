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
		'PSUseConsistentWhitespace',
		'PSUseCorrectCasing',
		'PSUseDeclaredVarsMoreThanAssignments',
		'PSUseLiteralInitializerForHashtable',
		'PSUseOutputTypeCorrectly',
		'PSUseProcessBlockForPipelineCommand',
		'PSUsePSCredentialType',
		'PSUseShouldProcessForStateChangingFunctions',
		'PSUseSingularNouns',
		'PSUseSupportsShouldProcess',
		'PSUseToExportFieldsInManifest',
		'PSUseUsingScopeModifierInNewRunspaces',
		'PSUseUTF8EncodingForHelpFile'
	)

	Rules        = @{
		PSAlignAssignmentStatement       = @{
			Enable         = $true
			CheckHashtable = $true
		}

		PSAvoidUsingPositionalParameters = @{
			CommandAllowList = 'Join-Path'
		}


		PSPlaceCloseBrace                = @{
			Enable       = $true
			NewLineAfter = $false
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
