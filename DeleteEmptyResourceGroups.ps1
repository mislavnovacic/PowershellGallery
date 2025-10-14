
# Connect to Azure account
Connect-AzAccount

# Get all resource groups with the specified prefix
$prefix = "RG-AVD-WEU-POC"
$resourceGroups = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "$prefix*" }

foreach ($rg in $resourceGroups) {
    # Check if the resource group is empty
    $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
    if ($resources.Count -eq 0) {
        Write-Host "Deleting empty resource group: $($rg.ResourceGroupName)"
        Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force
    } else {
        Write-Host "Skipping non-empty resource group: $($rg.ResourceGroupName)"
    }
}
