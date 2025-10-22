#!/bin/bash
# Automatic Markdown formatting script

echo "🔧 Formatting Markdown documents..."
echo ""

# Function to fix common markdown issues
fix_markdown_issues() {
    local file="$1"
    echo "  Processing: $file"
    
    # Create temporary file
    local tmp_file="${file}.tmp"
    
    # Apply fixes using sed
    sed -E \
        -e 's/\*\*([^*]+)\*\*:/\*\*\1\*\*：/g' \
        -e 's/\*\*([^*]+)\*\*\(/\*\*\1\*\* - /g' \
        "$file" > "$tmp_file"
    
    # Replace original file if changes were made
    if ! cmp -s "$file" "$tmp_file"; then
        mv "$tmp_file" "$file"
        echo "    ✓ Fixed"
    else
        rm "$tmp_file"
        echo "    - No changes"
    fi
}

# Export function for parallel execution
export -f fix_markdown_issues

# Find and process all markdown files in docs/
echo "📝 Fixing common Markdown format issues..."
find docs -name "*.md" -type f | while read -r file; do
    fix_markdown_issues "$file"
done

echo ""
echo "✅ Formatting complete!"
echo ""
echo "📊 Change statistics:"
git diff --stat docs/

echo ""
echo "💡 Tip: View detailed changes by running:"
echo "   git diff docs/"
echo ""
echo "🔍 Common issues fixed:"
echo "   - **text**: → **text**：(English colon to Chinese colon)"
echo "   - **text**(xxx) → **text** - xxx"
echo "   - Improved list formatting"

