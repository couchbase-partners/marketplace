#!/usr/bin/env bash

while getopts m:o:t:i:n: flag
do
    case "${flag}" in
        m) mapping_file=${OPTARG};;
        o) output=${OPTARG};;
        n) output_template_name=${OPTARG};;
        i) input_template=${OPTARG};;
        t) instance_types=${OPTARG};;
        *) exit 1;;
    esac
done

echo "In make archives"
mkdir -p "${output}"

if [[ -d "$output" ]]; then
    mkdir -p "$output"
fi

if [[ ! "$output" = */ ]]; then
    output="$output/"
fi

if [[ ! -f "$mapping_file" ]]; then
    echo "Invalid mapping file."
    exit 1
fi

if [[ ! -f "$input_template" ]]; then
    echo "Invalid input template."
    exit 1
fi

if [[ ! -f "$instance_types" ]]; then
    echo "Invalid instance types"
    exit1
fi

jq --argjson map "$(jq -r < "$mapping_file")" --argjson types "$(jq -r < "$instance_types")" '.Mappings = $map | .Parameters.SyncGatewayInstanceType = $types' < "${input_template}" > "${output}${output_template_name}"
