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
    # Global scripts: js/all/*.js — injected on every page
    ALL_DIR="$JS_DIR/all"
    if [ -d "$ALL_DIR" ]; then
        for js_file in "$ALL_DIR"/*.js; do
            [ -f "$js_file" ] || continue
            rel_path="${js_file#Resources/}"
            entries+=("{\"file\":\"$rel_path\",\"domain\":\"_all\",\"mode\":\"all\"}")
            echo "[CatExplorer] Indexed: $rel_path (global / all sites)"
        done
    fi

    # Per-domain scripts: js/<domain>/{strict,wildcard}/*.js
    for domain_dir in "$JS_DIR"/*/; do
        [ -d "$domain_dir" ] || continue
        domain=$(basename "$domain_dir")

        # Skip the 'all' folder (already handled above)
        [ "$domain" = "all" ] && continue

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
