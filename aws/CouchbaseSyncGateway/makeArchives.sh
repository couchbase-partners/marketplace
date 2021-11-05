#!/usr/bin/env bash

while getopts m:s:o:t:i:n: flag
do
    case "${flag}" in
        m) mapping_file=${OPTARG};;
        o) output=${OPTARG};;
        n) output_template_name=${OPTARG};;
        i) input_template=${OPTARG};;
        *) exit 1;;
    esac
done

echo "In make archives"
mkdir -p "${output}"

if [[ -d "$output" ]]; then
    echo "Invalid Output Directory."
    exit 1
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

jq --argjson map "$(jq -r < "$mapping_file")" '.Mappings = $map' < "${input_template}" > "${output}${output_template_name}"
