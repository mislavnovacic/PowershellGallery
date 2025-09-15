$featureVariables = [ordered]@{
    Online      = $true
    FeatureName = "MicrosoftWindowsPowerShellV2Root"
}

#Logging
Write-Host "Disable: $($featureVariables.FeatureName)"
$featureVariables | Format-Table -AutoSize | Write-output

#Disable Windows Feature
Disable-WindowsOptionalFeature @featureVariables
