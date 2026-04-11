#!/bin/bash
# Generates Resources/scripts.json from the Resources/js/ directory tree.
#
# Directory structure:
#   Resources/js/<domain>/strict/<Script>.js   — injected only on exact <domain> (and www.<domain>)
#   Resources/js/<domain>/wildcard/<Script>.js  — injected on <domain> and all subdomains (*.<domain>)
#
# Output: Resources/scripts.json
#   [{"file":"js/domain/mode/name.js","domain":"domain","mode":"strict"}, ...]
#
# The app reads scripts.json at startup and pre-loads all JS source into memory,
# so there's zero directory scanning at runtime.

JS_DIR="Resources/js"
OUTPUT="Resources/scripts.json"

# Build JSON array
entries=()

if [ -d "$JS_DIR" ]; then
    for domain_dir in "$JS_DIR"/*/; do
        [ -d "$domain_dir" ] || continue
        domain=$(basename "$domain_dir")

        for mode_dir in "$domain_dir"*/; do
            [ -d "$mode_dir" ] || continue
            mode=$(basename "$mode_dir")

            # Only allow strict and wildcard modes
            if [ "$mode" != "strict" ] && [ "$mode" != "wildcard" ]; then
                echo "[CatExplorer] Warning: unknown mode '$mode' in $domain_dir — skipping (use strict/ or wildcard/)"
                continue
            fi

            for js_file in "$mode_dir"*.js; do
                [ -f "$js_file" ] || continue
                # Path relative to Resources/ (matches bundle layout)
                rel_path="${js_file#Resources/}"
                entries+=("{\"file\":\"$rel_path\",\"domain\":\"$domain\",\"mode\":\"$mode\"}")
                echo "[CatExplorer] Indexed: $rel_path ($domain / $mode)"
            done
        done
    done
fi

# Write JSON
if [ ${#entries[@]} -eq 0 ]; then
    echo "[]" > "$OUTPUT"
else
    echo "[" > "$OUTPUT"
    for i in "${!entries[@]}"; do
        if [ $i -lt $((${#entries[@]} - 1)) ]; then
            echo "  ${entries[$i]}," >> "$OUTPUT"
        else
            echo "  ${entries[$i]}" >> "$OUTPUT"
        fi
    done
    echo "]" >> "$OUTPUT"
fi

echo "[CatExplorer] Generated $OUTPUT with ${#entries[@]} script(s)"
