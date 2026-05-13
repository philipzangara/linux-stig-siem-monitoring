#!/bin/bash

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
RESULTS_FILE="/var/log/openscap/stig-scan-$(date -u +"%Y%m%d-%H%M%S").xml"
SCORES_LOG="/var/log/openscap/compliance-scores.log"
PROFILE="xccdf_org.ssgproject.content_profile_stig"

# Locate SCAP content dynamically — searches common install locations
CONTENT=$(find /home /root /opt -name "ssg-ubuntu2404-ds.xml" 2>/dev/null | head -1)

if [ -z "$CONTENT" ]; then
  echo "$TIMESTAMP ERROR: ssg-ubuntu2404-ds.xml not found. Set CONTENT variable manually." >> "$SCORES_LOG"
  exit 1
fi

# Run the scan
oscap xccdf eval \
  --profile "$PROFILE" \
  --results "$RESULTS_FILE" \
  "$CONTENT" > /dev/null 2>&1

# Fix permissions so forwarder can read it
chmod o+r "$RESULTS_FILE"

# Extract and round the score
SCORE=$(grep -oP '(?<=<score system="urn:xccdf:scoring:default" maximum="100.000000">)[\d.]+' "$RESULTS_FILE" | awk '{printf "%.2f", $1}')

# Log it
echo "$TIMESTAMP host=$(hostname) scan=stig-scheduled compliance_score=$SCORE max_score=100 profile=stig-v1r1" \
  >> "$SCORES_LOG"

# Keep only 10 most recent XML files
ls -t /var/log/openscap/stig-scan-*.xml 2>/dev/null | tail -n +11 | xargs rm -f

