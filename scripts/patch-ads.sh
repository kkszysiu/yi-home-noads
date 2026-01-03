#!/bin/bash
set -e

DECOMPILED_DIR="$1"

if [ -z "$DECOMPILED_DIR" ]; then
    echo "Usage: $0 <decompiled_apk_directory>"
    exit 1
fi

if [ ! -d "$DECOMPILED_DIR" ]; then
    echo "Error: Directory $DECOMPILED_DIR does not exist"
    exit 1
fi

echo "=== Yi Home Ad Removal Patcher ==="
echo "Working directory: $DECOMPILED_DIR"

# Find SplashActivity.smali
echo ""
echo ">>> Looking for SplashActivity.smali..."
SPLASH_ACTIVITY=$(find "$DECOMPILED_DIR" -name "SplashActivity.smali" -path "*/com/ants360/yicamera/activity/*" | head -1)

if [ -z "$SPLASH_ACTIVITY" ]; then
    echo "Error: Could not find SplashActivity.smali"
    exit 1
fi
echo "Found: $SPLASH_ACTIVITY"

# Find AntsApplication$b.smali (the inner class handling resume ads)
echo ""
echo ">>> Looking for AntsApplication\$b.smali..."
ANTS_APP_B=$(find "$DECOMPILED_DIR" -name 'AntsApplication$b.smali' -path "*/com/ants360/yicamera/*" | head -1)

if [ -z "$ANTS_APP_B" ]; then
    echo "Warning: Could not find AntsApplication\$b.smali - skipping resume ads patch"
else
    echo "Found: $ANTS_APP_B"
fi

# Export variables for Python
export SPLASH_ACTIVITY
export ANTS_APP_B

# Patch SplashActivity.smali - modify g2() method to skip ads
echo ""
echo ">>> Patching SplashActivity.smali (splash ads)..."

python3 << 'PYTHON_SCRIPT'
import re
import os

splash_file = os.environ['SPLASH_ACTIVITY']

with open(splash_file, 'r') as f:
    content = f.read()

# Find and patch the g2() method - this is the main ad orchestration method
# We look for .method followed by g2()V and replace its body

g2_pattern = r'(\.method\s+(?:private|public)?\s*(?:final\s+)?g2\(\)V.*?\.locals\s+\d+)'
g2_match = re.search(g2_pattern, content, re.DOTALL)

if g2_match:
    # Find the full method
    method_start = content.find('.method', g2_match.start())
    method_end = content.find('.end method', g2_match.start())

    if method_start != -1 and method_end != -1:
        old_method = content[method_start:method_end + len('.end method')]

        # Extract method signature line
        method_lines = old_method.split('\n')
        method_sig = method_lines[0]

        # Create patched method that skips ads
        # Call f2(true) to proceed past splash, then k2() for initialization, then return
        new_method = f'''{method_sig}
    .locals 1

    # Patched: Skip all ad loading and go directly to main activity
    const/4 v0, 0x1

    invoke-direct {{p0, v0}}, Lcom/ants360/yicamera/activity/SplashActivity;->f2(Z)V

    invoke-direct {{p0}}, Lcom/ants360/yicamera/activity/SplashActivity;->k2()V

    return-void
.end method'''

        content = content.replace(old_method, new_method)
        print(f"Patched g2() method in SplashActivity")
    else:
        print("Warning: Could not find g2() method boundaries")
else:
    print("Warning: Could not find g2() method pattern")

with open(splash_file, 'w') as f:
    f.write(content)

print("SplashActivity patching complete")
PYTHON_SCRIPT

# Patch AntsApplication$b.smali - disable resume ads
if [ -n "$ANTS_APP_B" ]; then
    echo ""
    echo ">>> Patching AntsApplication\$b.smali (resume ads)..."

    python3 << 'PYTHON_SCRIPT2'
import re
import os

ants_file = os.environ['ANTS_APP_B']

with open(ants_file, 'r') as f:
    content = f.read()

# Find onActivityStarted method and add return-void at the beginning
# This prevents the 3-minute inactivity check from showing fullscreen ads

pattern = r'(\.method\s+public\s+onActivityStarted\(Landroid/app/Activity;\)V.*?\.locals\s+\d+)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    # Add return-void immediately after .locals declaration
    new_section = old_section + '\n\n    # Patched: Skip resume ad check\n    return-void\n'
    content = content.replace(old_section, new_section)
    print("Patched onActivityStarted() method in AntsApplication$b")
else:
    print("Warning: Could not find onActivityStarted() method pattern")

with open(ants_file, 'w') as f:
    f.write(content)

print("AntsApplication$b patching complete")
PYTHON_SCRIPT2
fi

echo ""
echo "=== Patching Complete ==="
echo "The following modifications were made:"
echo "  1. SplashActivity.g2() - bypasses splash screen ads"
if [ -n "$ANTS_APP_B" ]; then
    echo "  2. AntsApplication\$b.onActivityStarted() - disables resume ads"
fi
