#!/bin/bash -l

set -e

pwsh -noprofile -nologo -command "Import-Module '/arm-ttk/arm-ttk/arm-ttk.psd1'; Test-AzTemplate template/ ; if (\$Error.Count) { exit 1}"