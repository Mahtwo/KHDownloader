---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: Mahtwo

---

### Checklist
<!-- To fill checkmarks add a "x" like so: [x] -->
- [ ] **Mandatory**: This isn't a duplicate of an
[existing issue](https://github.com/Mahtwo/KHDownloader/issues?q=is%3Aissue%20),
including closed ones with label "wontfix".
- [ ] **Mandatory**: The bug happens on the
[latest version](https://github.com/Mahtwo/KHDownloader/releases) of KHDownloader.
If the bug happens randomly you can leave this unchecked and instead specify your version of KHDownloader.
- [ ] **Mandatory**: You are human and certify the bug wasn't hallucinated by AI.
This doesn't stop you from using AI to find real bugs (i.e. in source code),
but AI hallucinated slop with no human verifications will earn a permanent ban.

### Describe the bug
A clear and concise description of what the bug is.

### Commands executed (if applicable)
```powershell
$url = "foo"
khd -Url $url ...
```

### Expected behavior
A clear and concise description of what you expected to happen.

### Hardware and PowerShell
- OS and version: [e.g. Ubuntu 26.04, Windows 11 25H2]
- PowerShell version (use `$PSVersionTable.PSVersion.ToString()`): [e.g. 7.6.0]
- PowerShell RID (use `[System.Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier`): [e.g. win-x64]
- Additional informations (if applicable): [e.g. x64 PowerShell on ARM64 system, WSL]

### Additional context
Add any other context about the problem here.
