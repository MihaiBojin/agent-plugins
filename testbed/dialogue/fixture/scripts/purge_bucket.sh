#!/usr/bin/env bash
# Deletes every object in the production asset bucket. There is no undo.
# In this fixture the script only prints the command it would run.
echo "would run: aws s3 rm s3://inventory-prod-assets --recursive"
