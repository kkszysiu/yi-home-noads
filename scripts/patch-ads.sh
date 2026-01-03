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

echo "=== Yi Home Ad & Cloud Popup Removal Patcher ==="
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

# Find cloud-related files
echo ""
echo ">>> Looking for cloud popup files..."
FREE_CLOUD_DIALOG=$(find "$DECOMPILED_DIR" -name "FreeCloudDialogFragment.smali" -path "*/kamicloud/features/*" | head -1)
CLOUD_INTRO_ACTIVITY=$(find "$DECOMPILED_DIR" -name "CloudIntroductionsActivity.smali" -path "*/kamicloud/features/*" | head -1)
NO_CLOUD_INTRO_ACTIVITY=$(find "$DECOMPILED_DIR" -name "NoCloudIntroductionsActivity.smali" -path "*/kamicloud/features/*" | head -1)
CLOUD_FEATURES_ACTIVITY=$(find "$DECOMPILED_DIR" -name "CloudFeaturesActivity.smali" -path "*/kamicloud/features/*" | head -1)
SMART_AI_DIALOG=$(find "$DECOMPILED_DIR" -name "SmartAIPurchaseDialog.smali" -path "*/kamicloud/features/*" | head -1)

[ -n "$FREE_CLOUD_DIALOG" ] && echo "Found: $FREE_CLOUD_DIALOG"
[ -n "$CLOUD_INTRO_ACTIVITY" ] && echo "Found: $CLOUD_INTRO_ACTIVITY"
[ -n "$NO_CLOUD_INTRO_ACTIVITY" ] && echo "Found: $NO_CLOUD_INTRO_ACTIVITY"
[ -n "$CLOUD_FEATURES_ACTIVITY" ] && echo "Found: $CLOUD_FEATURES_ACTIVITY"
[ -n "$SMART_AI_DIALOG" ] && echo "Found: $SMART_AI_DIALOG"

# Export variables for Python
export SPLASH_ACTIVITY
export ANTS_APP_B
export FREE_CLOUD_DIALOG
export CLOUD_INTRO_ACTIVITY
export NO_CLOUD_INTRO_ACTIVITY
export CLOUD_FEATURES_ACTIVITY
export SMART_AI_DIALOG

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
g2_pattern = r'(\.method\s+(?:private|public)?\s*(?:final\s+)?g2\(\)V.*?\.locals\s+\d+)'
g2_match = re.search(g2_pattern, content, re.DOTALL)

if g2_match:
    method_start = content.find('.method', g2_match.start())
    method_end = content.find('.end method', g2_match.start())

    if method_start != -1 and method_end != -1:
        old_method = content[method_start:method_end + len('.end method')]
        method_lines = old_method.split('\n')
        method_sig = method_lines[0]

        new_method = f'''{method_sig}
    .locals 1

    # Patched: Skip all ad loading and go directly to main activity
    const/4 v0, 0x1

    invoke-direct {{p0, v0}}, Lcom/ants360/yicamera/activity/SplashActivity;->f2(Z)V

    invoke-direct {{p0}}, Lcom/ants360/yicamera/activity/SplashActivity;->k2()V

    return-void
.end method'''

        content = content.replace(old_method, new_method)
        print("Patched g2() method in SplashActivity")
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

pattern = r'(\.method\s+public\s+onActivityStarted\(Landroid/app/Activity;\)V.*?\.locals\s+\d+)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
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

# Patch FreeCloudDialogFragment - make it dismiss immediately
if [ -n "$FREE_CLOUD_DIALOG" ]; then
    echo ""
    echo ">>> Patching FreeCloudDialogFragment.smali (cloud popup)..."

    python3 << 'PYTHON_FREE_CLOUD'
import re
import os

dialog_file = os.environ['FREE_CLOUD_DIALOG']

with open(dialog_file, 'r') as f:
    content = f.read()

# Patch onViewCreated to immediately dismiss
pattern = r'(\.method\s+public\s+onViewCreated\(Landroid/view/View;Landroid/os/Bundle;\)V.*?\.locals\s+\d+)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    new_section = old_section + '''

    # Patched: Immediately dismiss cloud popup
    invoke-virtual {p0}, Landroidx/fragment/app/DialogFragment;->dismiss()V

    return-void
'''
    content = content.replace(old_section, new_section)
    print("Patched onViewCreated() in FreeCloudDialogFragment")
else:
    print("Warning: Could not find onViewCreated() method pattern")

with open(dialog_file, 'w') as f:
    f.write(content)
PYTHON_FREE_CLOUD
fi

# Patch CloudIntroductionsActivity - make it finish immediately
if [ -n "$CLOUD_INTRO_ACTIVITY" ]; then
    echo ""
    echo ">>> Patching CloudIntroductionsActivity.smali (cloud intro)..."

    python3 << 'PYTHON_CLOUD_INTRO'
import re
import os

activity_file = os.environ['CLOUD_INTRO_ACTIVITY']

with open(activity_file, 'r') as f:
    content = f.read()

# Patch onCreate to immediately finish
pattern = r'(\.method\s+public\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    new_section = old_section + '''

    # Patched: Skip cloud introduction and finish immediately
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    return-void
'''
    content = content.replace(old_section, new_section)
    print("Patched onCreate() in CloudIntroductionsActivity")
else:
    print("Warning: Could not find onCreate() method pattern in CloudIntroductionsActivity")

with open(activity_file, 'w') as f:
    f.write(content)
PYTHON_CLOUD_INTRO
fi

# Patch NoCloudIntroductionsActivity - make it finish immediately
if [ -n "$NO_CLOUD_INTRO_ACTIVITY" ]; then
    echo ""
    echo ">>> Patching NoCloudIntroductionsActivity.smali (no cloud intro)..."

    python3 << 'PYTHON_NO_CLOUD_INTRO'
import re
import os

activity_file = os.environ['NO_CLOUD_INTRO_ACTIVITY']

with open(activity_file, 'r') as f:
    content = f.read()

pattern = r'(\.method\s+public\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    new_section = old_section + '''

    # Patched: Skip no-cloud introduction and finish immediately
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    return-void
'''
    content = content.replace(old_section, new_section)
    print("Patched onCreate() in NoCloudIntroductionsActivity")
else:
    print("Warning: Could not find onCreate() method pattern in NoCloudIntroductionsActivity")

with open(activity_file, 'w') as f:
    f.write(content)
PYTHON_NO_CLOUD_INTRO
fi

# Patch CloudFeaturesActivity - make it finish immediately
if [ -n "$CLOUD_FEATURES_ACTIVITY" ]; then
    echo ""
    echo ">>> Patching CloudFeaturesActivity.smali (cloud features)..."

    python3 << 'PYTHON_CLOUD_FEATURES'
import re
import os

activity_file = os.environ['CLOUD_FEATURES_ACTIVITY']

with open(activity_file, 'r') as f:
    content = f.read()

pattern = r'(\.method\s+public\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    new_section = old_section + '''

    # Patched: Skip cloud features and finish immediately
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    return-void
'''
    content = content.replace(old_section, new_section)
    print("Patched onCreate() in CloudFeaturesActivity")
else:
    print("Warning: Could not find onCreate() method pattern in CloudFeaturesActivity")

with open(activity_file, 'w') as f:
    f.write(content)
PYTHON_CLOUD_FEATURES
fi

# Patch SmartAIPurchaseDialog - make it dismiss immediately
if [ -n "$SMART_AI_DIALOG" ]; then
    echo ""
    echo ">>> Patching SmartAIPurchaseDialog.smali (AI purchase popup)..."

    python3 << 'PYTHON_SMART_AI'
import re
import os

dialog_file = os.environ['SMART_AI_DIALOG']

with open(dialog_file, 'r') as f:
    content = f.read()

# Patch onViewCreated or show method
pattern = r'(\.method\s+public\s+onViewCreated\(Landroid/view/View;Landroid/os/Bundle;\)V.*?\.locals\s+\d+)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_section = match.group(0)
    new_section = old_section + '''

    # Patched: Immediately dismiss AI purchase popup
    invoke-virtual {p0}, Landroidx/fragment/app/DialogFragment;->dismiss()V

    return-void
'''
    content = content.replace(old_section, new_section)
    print("Patched onViewCreated() in SmartAIPurchaseDialog")
else:
    print("Warning: Could not find onViewCreated() method pattern in SmartAIPurchaseDialog")

with open(dialog_file, 'w') as f:
    f.write(content)
PYTHON_SMART_AI
fi

echo ""
echo "=== Patching Complete ==="
echo "The following modifications were made:"
echo "  1. SplashActivity.g2() - bypasses splash screen ads"
[ -n "$ANTS_APP_B" ] && echo "  2. AntsApplication\$b.onActivityStarted() - disables resume ads"
[ -n "$FREE_CLOUD_DIALOG" ] && echo "  3. FreeCloudDialogFragment - auto-dismisses cloud popup"
[ -n "$CLOUD_INTRO_ACTIVITY" ] && echo "  4. CloudIntroductionsActivity - skips cloud introduction"
[ -n "$NO_CLOUD_INTRO_ACTIVITY" ] && echo "  5. NoCloudIntroductionsActivity - skips no-cloud intro"
[ -n "$CLOUD_FEATURES_ACTIVITY" ] && echo "  6. CloudFeaturesActivity - skips cloud features screen"
[ -n "$SMART_AI_DIALOG" ] && echo "  7. SmartAIPurchaseDialog - auto-dismisses AI purchase popup"
