#!/bin/bash
# Generates entitlements.plist from Resources/config.json
# Run during build: ./gen_entitlements.sh

CONFIG="Resources/config.json"
OUTPUT="entitlements.plist"

# Start fresh plist
cat > "$OUTPUT" << 'HEADER'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
HEADER

# Read entitlements array from config.json
if [ -f "$CONFIG" ]; then
    # Use python3 to parse JSON (available on macOS)
    python3 -c "
import json, sys
with open('$CONFIG') as f:
    cfg = json.load(f)
for ent in cfg.get('entitlements', []):
    print('    <key>{}</key>'.format(ent))
    print('    <true/>')
" >> "$OUTPUT" 2>/dev/null
fi

cat >> "$OUTPUT" << 'FOOTER'
</dict>
</plist>
FOOTER

echo "[CatExplorer] Generated $OUTPUT"
