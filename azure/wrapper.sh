#!/bin/bash -l

set -e

_args="-TemplatePath '$1'"

echo "Running: sh /arm-ttk/arm-ttk/Test-AzTemplate.sh $_args"
results=$(sh /arm-ttk/arm-ttk/Test-AzTemplate.sh "$_args")

echo "$results"

#Remove control characters before checking for failure
results=$(echo "$results" | col -b)
results=${results//0m/}
results=${results//32m/}
results=${results//35m/}
results=${results//32;1m/}
results=${results//1;31m/}

if [[ "$results" != *"Fail  : 0"* ]]; then
    exit 1
fi