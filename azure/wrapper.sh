#!/bin/bash -l

set -e

pwsh -noprofile -nologo -command "Import-Module '/arm-ttk/arm-ttk/arm-ttk.psd1'; Test-AzTemplate template/ -Skip Allowed-Values-Should-Actually-Be-Allowed ; if (\$Error.Count) { exit 1}"
