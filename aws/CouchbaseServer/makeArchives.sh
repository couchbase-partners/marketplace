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

cat "${input_template}" | jq --argjson map "$(cat "$mapping_file" | jq -r)" '.Mappings = $map' > "${output}${output_template_name}"
