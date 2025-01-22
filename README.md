# Test-W11Compatibility.ps1
 This script is intended to run within a ConfigMgr Task Sequence. It checks a system's compatibility with Windows 11, including UEFI, Secure Boot, TPM, and processor compatibility.

![Test-W11Compatibility](Test-W11Compatibility.png)

## Features

- **UEFI Check**: Verifies if the system firmware is UEFI.
- **Secure Boot Check**: Ensures that Secure Boot is enabled.
- **TPM Check**: Confirms the presence of TPM 2.0.
- **Processor Compatibility**: Checks if the processor is supported by Windows 11. This check pulls live data from Microsoft's documentation site to ensure the most up-to-date compatibility information.
- **ConfigMgr Task Sequnce integration**: Script uses Task Sequence Environment COM Object, and Progress UI COM Object

## Requirements

- Windows PowerShell 5.1
- MDT integrated Task Sequence or Similar to provide Task Sequence Environment variables
- WinPE 10 or later
- Internet access to retrieve the Windows 11 supported processor lists from Microsoft

## ToDo

- Enable CPU testing on VMs. -- Currently VMs don't get a CPU test, because my ConfigMgr testing Hyper-V server is too old.
- Add parameter to select Windows 11 Release checking i.e. 21H2, 22H2, or 23H2 -- As of 2024.12.13 it's 22H2/23H2
- Add ability to cache compatible processors for offline use.

## License

This project is licensed under the GPLv3 License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Author

- Eden Nelson - [EdenNelson](https://github.com/EdenNelson)
