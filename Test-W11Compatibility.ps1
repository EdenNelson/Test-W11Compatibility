<#
.SYNOPSIS
    This script intended to run within a ConfigMgr Task Sequnce, it checks the compatibility of a system with Windows 11, including UEFI, Secure Boot, TPM, and processor compatibility.

.DESCRIPTION
    The script performs the following tasks:
    - Sets up Task Sequence Environment and Progress UI.
    - Retrieves Task Sequence Variables.
    - Checks if the system is a Virtual Machine and performs compatibility checks accordingly.
    - For physical machines, it checks the processor compatibility against the Windows 11 supported processor lists from Microsoft.
    - Verifies UEFI, Secure Boot, and TPM 2.0 compatibility.
    - Displays appropriate messages and error dialogs based on the compatibility checks.
    
.FUNCTION Get-TableDataFromWebRequest
    Retrieves table data from a web request.
    - Modififed from the original function by Lee Holmes.
    - @LeeHolmes
    - https://www.leeholmes.com/extracting-tables-from-powershells-invoke-webrequest/

.NOTES
    Author: Eden Nelson @EdenNelson
    Version: 2024.12.13.0
.EXAMPLE
    .\Test-Win11Compat.ps1
    Runs the script to check Windows 11 compatibility on the current system.
.REQUIRES
    - PowerShell 5.1 or later
    - MDT integrated Task Sequence or Similar to provide Task Sequence Environment variables
    - WinPE 10 or later
    - Internet access to retrieve the Windows 11 supported processor lists from Microsoft
#>

# Task Sequence Environment COM Object Setup
$TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
# Task Sequence Variables
$BootedUEFI = $TSEnv.Value("_SMSTSBootUEFI")
$SecureBoot = $TSEnv.Value("_TSSecureBoot")
$TPMisActive = $TSEnv.Value("TPMIsActive")
$TPMisEnabled = $TSEnv.Value("TPMIsEnabled")
$TPMIsV2 = $TSEnv.Value("TPMIsV2")
$IsVM = $TSEnv.Value("IsVM")


# Progress UI COM Object Setup
$TSProgressUi = New-Object -ComObject Microsoft.SMS.TSProgressUI
# Progress UI Variables
$OrganizationName = "Cascade Technology Alliance"
$TSPackageName = $TSEnv.Value("_SMSTSPackageName")
$ErrorCode = '1'
$CustomTitle = "Running: $($TSEnv.Value("_SMSTSPackageName"))"
$ErrorMessage = "Task Sequence $($TSEnv.Value("_SMSTSPackageName")) has failed with error code $($TSEnv.Value("ErrorReturnCode")) in the task sequence step $($TSEnv.Value("ErrorStep")).`r`n"
$ErrorMessage += "Please Do not ignore this error."
$TimeoutInSeconds = '604800'
$reboot = '0'
$TSStepName = $TSEnv.Value("ErrorStep")


# CPU Compatibility data
# Processor Manufacturer list
$ManufacturerList = @("Intel", "AMD", "Qualcomm")

# This script will check if the processor in the system is compatible with Windows 11 22H2/23H2
$URIW11IntelProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-22h2-supported-intel-processors"
$URIW11AMDProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-22h2-supported-amd-processors"
$URIW11QualcommProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-22h2-supported-qualcomm-processors"

# Get the processor information
$Win32Processor = ((Get-CimInstance -ClassName Win32_Processor).name -split ' ' | Select-Object -First 3) -replace '\(R\)', '' -replace '\(TM\)'

# Create a hashtable with the processor information
$Processor = @{}
$Processor.Add("Manufacturer", $Win32Processor[0])
$Processor.Add("Brand", $Win32Processor[1])
$Processor.Add("Model", $Win32Processor[2])

# Get the processor information table from the LIVE Microsoft website
function Get-TableDataFromWebRequest {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.PowerShell.Commands.HtmlWebResponseObject] $WebRequest,
      
        [Parameter(Mandatory = $true)]
        [int] $TableNumber
    )

    # Extract the tables out of the web request
    $tables = @($WebRequest.ParsedHtml.getElementsByTagName("TABLE"))
    $table = $tables[$TableNumber]
    $titles = @()
    $rows = @($table.Rows)

    # Go through all of the rows in the table
    foreach ($row in $rows) {
        $cells = @($row.Cells)
       
        # If we've found a table header, remember its titles
        if ($cells[0].tagName -eq "TH") {
            $titles = @($cells | % { ("" + $_.InnerText).Trim() })
            continue
        }

        # If we haven't found any table headers, make up names "P1", "P2", etc.
        if (-not $titles) {
            $titles = @(1..($cells.Count + 2) | % { "P$_" })
        }

        # Now go through the cells in the the row. For each, try to find the
        # title that represents that column and create a hashtable mapping those
        # titles to content
        $resultObject = [Ordered] @{ }
        for ($counter = 0; $counter -lt $cells.Count; $counter++) {
            $title = $titles[$counter]
            if (-not $title) { continue }  

            $resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
        }

        # And finally cast that hashtable to a PSCustomObject
        [PSCustomObject] $resultObject
    }
}


#Main Script

if ($IsVM -eq "True") {
    Write-Output "This is a Virtual Machine"
    Write-Output "Skipping most Windows 11 Compatibility checks"

    if ($BootedUEFI -and $SecureBoot -and $TPMisActive -and $TPMisEnabled -and $TPMisEnabled -and $TPMIsV2) {
        Write-Output "VM components are compatible with Windows 11 including UEFI, Secure Boot and TPM 2.0"
    } else {
        Write-Output "Not all components are compatible with Windows 11"

        Write-Output "Booted UEFI: $BootedUEFI"
        Write-Output "Secure Boot: $SecureBoot"
        Write-Output "TPM is Active: $TPMisActive"
        Write-Output "TPM is Enabled: $TPMisEnabled"
        Write-Output "TPM is Version 2.0: $TPMIsV2"

        # Close the default Task Sequence Progress dialog
        $TSProgressUi.CloseProgressDialog()
        # Show the custom error dialog
        $TSProgressUi.ShowErrorDialog($OrganizationName, $TSPackageName, $CustomTitle, $ErrorMessage, $ErrorCode, $TimeoutInSeconds, $Reboot, $TSStepName)
        Exit 1
    }

} else {
    Write-Output "This is a Physical Machine"
    Write-Output "Checking All Windows 11 Compatibility"

    # Check the processor compatibility with Windows 11
    Remove-Variable -Name CompatProc -ErrorAction SilentlyContinue
    switch ($Processor.Manufacturer) {
        Intel {
            Write-Output "Installed Processor is an Intel Processor"
            Write-Output "Getting Intel Processor Compatibility List"
            Try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11IntelProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®",''  -replace 'â','' -replace '¢',''
            }
            Catch {
                Write-Verbose -Message "Error getting the Intel Processor Compatibility List"
                Exit 1
            }
        }
        AMD {
            Write-Output "Installed Processor is an AMD Processor"
            Write-Output "Getting AMD Processor Compatibility List"
            try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11AMDProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®",''  -replace 'â','' -replace '¢',''
            }
            Catch {
                Write-Verbose -Message "Error getting the AMD Processor Compatibility List"
                Exit 1
            }
        }
        Qualcomm {
            Write-Output "Installed Processor is a Qualcomm Processor"
            Write-Output "Getting Qualcomm Processor Compatibility List"
            try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11QualcommProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®",''  -replace 'â','' -replace '¢',''
            }
            Catch {
                Write-Verbose -Message "Error getting the Qualcomm Processor Compatibility List"
                Exit 1
            }
        }
        Default {
            Write-Verbose -Message "Installed Processor is not an Intel, AMD or Qualcomm Processor"
            Exit 1
        }
    }

    # Check if the processor Manufacturer is in the static compatibility list
    Remove-Variable -Name ManufacturerIsCompatible -ErrorAction SilentlyContinue
    $Processor.Manufacturer | ForEach-Object {
        Write-Output "Checking if the Manufacturer of Installed $($Processor.Manufacturer) $($Processor.Brand) $($Processor.Model) is compatible with Windows 11"
        Write-Output  "Attempting to matching with $_ from the compatibility list"
        if ($ManufacturerList -match $_) {
            $ManufacturerIsCompatible = $true
        }
    }

    # Check if the processor is in the compatibility list
    Remove-Variable -Name BrandIsCompatible -ErrorAction SilentlyContinue
    $Processor.Brand | ForEach-Object {
        Write-Output "Checking if the Brand of Installed $($Processor.Manufacturer) $($Processor.Brand) $($Processor.Model) is compatible with Windows 11"
        Write-Output  "Attempting to matching with $_ from the compatibility list"
        if ($CompatProc -match $_) {
            $BrandIsCompatible = $true
        }
    }

    # Check if the processor is in the compatibility list
    Remove-Variable -Name ModelIsCompatible -ErrorAction SilentlyContinue
    $Processor.Model | ForEach-Object {
        Write-Output "Checking if the Model of Installed $($Processor.Manufacturer) $($Processor.Brand) $($Processor.Model) is compatible with Windows 11"
        Write-Output  "Attempting to matching with $_ from the compatibility list"
        if ($CompatProc -match $_) {
            $ModelIsCompatible = $true
        }
    }

    # Check if all components are compatible
    if ($ManufacturerIsCompatible -and $BrandIsCompatible -and $ModelIsCompatible -and $BootedUEFI -and $SecureBoot -and $TPMisActive -and $TPMisEnabled -and $TPMisEnabled -and $TPMIsV2) {
        Write-Output "All components are compatible with Windows 11 including the Processor, UEFI, Secure Boot and TPM 2.0"
        exit 0
    } else {
        Write-Output "Not all components are compatible with Windows 11"

        Write-Output "processor Manufacturer: $ManufacturerIsCompatible"
        Write-Output "processor Brand: $BrandIsCompatible"
        Write-Output "processor Model: $ModelIsCompatible"
        Write-Output "Booted UEFI: $BootedUEFI"
        Write-Output "Secure Boot: $SecureBoot"
        Write-Output "TPM is Active: $TPMisActive"
        Write-Output "TPM is Enabled: $TPMisEnabled"
        Write-Output "TPM is Version 2.0: $TPMIsV2"
        # Close the default Task Sequence Progress dialog
        $TSProgressUi.CloseProgressDialog()
        # Show the custom error dialog
        $TSProgressUi.ShowErrorDialog($OrganizationName, $TSPackageName, $CustomTitle, $ErrorMessage, $ErrorCode, $TimeoutInSeconds, $Reboot, $TSStepName)
        Exit 1
    }
}

