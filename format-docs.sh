#!/bin/bash
# Automatic Markdown formatting script

echo "🔧 Formatting Markdown documents..."

# Format all documents
markdownlint --fix "docs/**/*.md"

echo "✅ Formatting complete!"
echo ""
echo "📊 Change statistics:"
git diff --stat docs/

echo ""
echo "💡 Tip: View detailed changes by running:"
echo "   git diff docs/"

