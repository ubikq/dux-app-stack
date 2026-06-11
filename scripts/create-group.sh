#!/usr/bin/env bash
# Creates a new independent App Group plugin copy with a unique ID.
# Usage: create-group.sh <source_plugin_dir> <new_group_id> <new_group_name>
#
# Arguments:
#   source_plugin_dir  Absolute path to the source plugin directory
#   new_group_id       Unique alphanumeric ID for the new group (e.g. "mediaApps")
#   new_group_name     Display name for the new group (e.g. "Media")
#
# After running, go to DMS Settings → Plugins → Scan for Plugins → enable the
# new group → add it to DankBar via Settings → DankBar.

set -euo pipefail

SOURCE_DIR="${1:-}"
NEW_ID="${2:-}"
NEW_NAME="${3:-}"

if [[ -z "$SOURCE_DIR" || -z "$NEW_ID" || -z "$NEW_NAME" ]]; then
    echo "Error: Missing arguments." >&2
    echo "Usage: create-group.sh <source_dir> <new_id> <new_name>" >&2
    exit 1
fi

if [[ ! "$NEW_ID" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    echo "Error: ID must start with a letter and contain only letters, numbers, underscores, or hyphens." >&2
    exit 1
fi

DEST_DIR="$HOME/.config/DankMaterialShell/plugins/$NEW_ID"

if [[ -d "$DEST_DIR" ]]; then
    echo "Error: Plugin directory already exists: $DEST_DIR" >&2
    exit 2
fi

# Copy plugin directory
cp -r "$SOURCE_DIR" "$DEST_DIR"

# Patch plugin.json — sed is safe here because plugin.json has a known,
# controlled format and the ID/name values are already validated above.
sed -i "s/\"id\": \"[^\"]*\"/\"id\": \"$NEW_ID\"/" "$DEST_DIR/plugin.json"
sed -i "s/\"name\": \"[^\"]*\"/\"name\": \"$NEW_NAME\"/" "$DEST_DIR/plugin.json"
sed -i "s/\"description\": \"[^\"]*\"/\"description\": \"App Group — $NEW_NAME\"/" "$DEST_DIR/plugin.json"

# Patch pluginId in AppGroupSettings.qml
sed -i "s/pluginId: \"[^\"]*\"/pluginId: \"$NEW_ID\"/" "$DEST_DIR/AppGroupSettings.qml"

echo "Created: $DEST_DIR"
echo "Next steps:"
echo "  1. DMS Settings → Plugins → Scan for Plugins"
echo "  2. Enable '$NEW_NAME'"
echo "  3. DMS Settings → DankBar → add '$NEW_NAME' to your bar"
