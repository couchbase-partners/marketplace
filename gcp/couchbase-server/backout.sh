#!/bin/bash

while getopts n: flag
do
    case "${flag}" in
        n) STACK_NAME=${OPTARG};;
        *) exit 1;;
    esac
done
 gcloud deployment-manager deployments delete "$STACK_NAME" -q 