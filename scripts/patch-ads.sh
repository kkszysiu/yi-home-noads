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
NATIVE_AD_UTIL=$(find "$DECOMPILED_DIR" -name "NativeAdvertisingGoogleAdUtil.smali" -path "*/com/ants360/yicamera/util/*" | head -1)
AD_DIALOG_ACTIVITY=$(find "$DECOMPILED_DIR" -name "AdDialogFragment.smali" -path "*/com/ants360/yicamera/fragment/*" | head -1)
GOOGLE_AD_MANAGER=$(find "$DECOMPILED_DIR" -name "l0.smali" -path "*/com/ants360/yicamera/base/*" | head -1)

[ -n "$FREE_CLOUD_DIALOG" ] && echo "Found: $FREE_CLOUD_DIALOG"
[ -n "$CLOUD_INTRO_ACTIVITY" ] && echo "Found: $CLOUD_INTRO_ACTIVITY"
[ -n "$NO_CLOUD_INTRO_ACTIVITY" ] && echo "Found: $NO_CLOUD_INTRO_ACTIVITY"
[ -n "$CLOUD_FEATURES_ACTIVITY" ] && echo "Found: $CLOUD_FEATURES_ACTIVITY"
[ -n "$SMART_AI_DIALOG" ] && echo "Found: $SMART_AI_DIALOG"
[ -n "$NATIVE_AD_UTIL" ] && echo "Found: $NATIVE_AD_UTIL"
[ -n "$AD_DIALOG_ACTIVITY" ] && echo "Found: $AD_DIALOG_ACTIVITY"
[ -n "$GOOGLE_AD_MANAGER" ] && echo "Found: $GOOGLE_AD_MANAGER"

# Export variables for Python
export SPLASH_ACTIVITY
export ANTS_APP_B
export FREE_CLOUD_DIALOG
export CLOUD_INTRO_ACTIVITY
export NO_CLOUD_INTRO_ACTIVITY
export CLOUD_FEATURES_ACTIVITY
export SMART_AI_DIALOG
export NATIVE_AD_UTIL
export AD_DIALOG_ACTIVITY
export GOOGLE_AD_MANAGER

# Patch SplashActivity.smali - modify r2() method to skip ads
echo ""
echo ">>> Patching SplashActivity.smali (splash ads)..."

python3 << 'PYTHON_SCRIPT'
import re
import os

splash_file = os.environ['SPLASH_ACTIVITY']

with open(splash_file, 'r') as f:
    content = f.read()

# Patch known splash ad loaders to immediately jump to main flow.
patched_methods = []

for method_name in ['r2', 's2']:
    pattern = rf'(\.method\s+private\s+final\s+{method_name}\(\)V.*?\.locals\s+\d+)'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        continue

    method_start = content.find('.method', match.start())
    method_end = content.find('.end method', match.start())

    if method_start == -1 or method_end == -1:
        print(f"Warning: Could not find {method_name}() method boundaries")
        continue

    old_method = content[method_start:method_end + len('.end method')]
    method_lines = old_method.split('\n')
    method_sig = method_lines[0]

    new_method = f'''{method_sig}
    .locals 0

    # Patched: Skip splash ad loading and go directly to main activity
    invoke-direct {{p0}}, Lcom/ants360/yicamera/activity/SplashActivity;->y2()V

    return-void
.end method'''

    content = content.replace(old_method, new_method)
    patched_methods.append(method_name)
    print(f"Patched {method_name}() in SplashActivity - ads bypassed")

# Patch Yi-hosted splash promo flow as well.
g2_pattern = r'(\.method\s+private\s+final\s+G2\(Lcom/xiaoyi/cloud/newCloud/bean/BannerDetailInfo\$BannerDetailBean;\)V)(.*?)(\.end method)'
g2_match = re.search(g2_pattern, content, re.DOTALL)
if g2_match:
    g2_method = '''.method private final G2(Lcom/xiaoyi/cloud/newCloud/bean/BannerDetailInfo$BannerDetailBean;)V
    .locals 0

    # Patched: Skip Yi splash promo and continue startup
    invoke-direct {p0}, Lcom/ants360/yicamera/activity/SplashActivity;->y2()V

    return-void
.end method'''
    content = re.sub(g2_pattern, g2_method, content, count=1, flags=re.DOTALL)
    patched_methods.append('G2')
    print("Patched G2(...) in SplashActivity - Yi splash promo bypassed")

if not patched_methods:
    # Try alternative method names (obfuscation may vary)
    for method_name in ['q2', 't2', 'p2']:
        alt_pattern = rf'(\.method\s+private\s+final\s+{method_name}\(\)V.*?\.locals\s+\d+)'
        alt_match = re.search(alt_pattern, content, re.DOTALL)
        if alt_match:
            print(f"Found alternative ad method candidate: {method_name}()")
            break
    else:
        print("Warning: Could not find splash ad loading method patterns (r2/s2 or alternatives)")

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

# Patch onCreate to immediately finish (handles both public and protected)
pattern = r'(\.method\s+(?:public|protected)\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
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

pattern = r'(\.method\s+(?:public|protected)\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
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

pattern = r'(\.method\s+(?:public|protected)\s+onCreate\(Landroid/os/Bundle;\)V.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)'
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

# Patch NativeAdvertisingGoogleAdUtil - disable in-app banner/native ad entrypoints
if [ -n "$NATIVE_AD_UTIL" ]; then
    echo ""
    echo ">>> Patching NativeAdvertisingGoogleAdUtil.smali (global ad entrypoints)..."

    python3 << 'PYTHON_NATIVE_AD_UTIL'
import os
import re

util_file = os.environ['NATIVE_AD_UTIL']

with open(util_file, 'r') as f:
    content = f.read()

targets = [
    ('D', '(Landroid/widget/FrameLayout;)V'),
    ('E', '(Landroid/widget/FrameLayout;)V'),
    ('H', '(Landroid/widget/FrameLayout;)V'),
    ('I', '(Landroid/widget/FrameLayout;)V'),
    ('J', '(Landroid/widget/FrameLayout;)V'),
    ('O', '(Landroid/widget/FrameLayout;Lcom/xiaoyi/cloud/newCloud/bean/BannerDetailInfo$BannerDetailBean;Landroid/app/Activity;Lcom/ants360/yicamera/util/NativeAdvertisingGoogleAdUtil$a;)V'),
    ('W', '(Landroid/widget/FrameLayout;Lcom/xiaoyi/cloud/newCloud/bean/BannerDetailInfo$BannerDetailBean;Landroid/app/Activity;Lcom/ants360/yicamera/util/NativeAdvertisingGoogleAdUtil$b;I)V'),
    ('a0', '()V'),
    ('w', '()V'),
]

patched_count = 0

for name, descriptor in targets:
    pattern = rf'(\.method[^\n]*\s{name}{re.escape(descriptor)}\n)(.*?)(\.end method)'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        print(f"Warning: Could not find method {name}{descriptor}")
        continue

    method_sig = match.group(1).rstrip('\n')
    new_method = f'''{method_sig}
    .locals 0

    # Patched: Disable ad entrypoint {name}()
    return-void
.end method'''

    old_method = match.group(0)
    content = content.replace(old_method, new_method, 1)
    patched_count += 1
    print(f"Patched {name}{descriptor}")

with open(util_file, 'w') as f:
    f.write(content)

print(f"NativeAdvertisingGoogleAdUtil patching complete ({patched_count} methods patched)")
PYTHON_NATIVE_AD_UTIL
fi

# Patch AdDialogFragment - skip ad dialog activity entirely
if [ -n "$AD_DIALOG_ACTIVITY" ]; then
    echo ""
    echo ">>> Patching AdDialogFragment.smali (skip ad dialog activity)..."

    python3 << 'PYTHON_AD_DIALOG'
import os
import re

dialog_file = os.environ['AD_DIALOG_ACTIVITY']

with open(dialog_file, 'r') as f:
    content = f.read()

on_create_pattern = r'(\.method\s+public\s+onCreate\(Landroid/os/Bundle;\)V)(.*?)(\.end method)'
on_create_match = re.search(on_create_pattern, content, re.DOTALL)

if on_create_match:
    method_sig = on_create_match.group(1)
    new_method = f'''{method_sig}
    .locals 0

    # Patched: Skip ad dialog activity
    invoke-super {{p0, p1}}, Lcom/xiaoyi/base/ui/BaseActivity;->onCreate(Landroid/os/Bundle;)V
    invoke-virtual {{p0}}, Landroid/app/Activity;->finish()V
    return-void
.end method'''
    content = content.replace(on_create_match.group(0), new_method, 1)
    print("Patched AdDialogFragment.onCreate()")
else:
    print("Warning: Could not find AdDialogFragment.onCreate()")

# Also hard-disable AnyThink/Yd splash loaders in case this activity is reached by another path.
for method_name in ['j2', 'k2']:
    pattern = rf'(\.method\s+private\s+{method_name}\(\)V)(.*?)(\.end method)'
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        print(f"Warning: Could not find AdDialogFragment.{method_name}()")
        continue
    replacement = f'''.method private {method_name}()V
    .locals 0

    # Patched: Disable ad loader {method_name}() and close ad activity
    invoke-direct {{p0}}, Lcom/ants360/yicamera/fragment/AdDialogFragment;->x2()V
    return-void
.end method'''
    content = re.sub(pattern, replacement, content, count=1, flags=re.DOTALL)
    print(f"Patched AdDialogFragment.{method_name}()")

with open(dialog_file, 'w') as f:
    f.write(content)
PYTHON_AD_DIALOG
fi

# Patch GoogleAdManager (l0) - disable app-open/interstitial ad flow
if [ -n "$GOOGLE_AD_MANAGER" ]; then
    echo ""
    echo ">>> Patching l0.smali (Google ad manager)..."

    python3 << 'PYTHON_GOOGLE_AD_MANAGER'
import os
import re

manager_file = os.environ['GOOGLE_AD_MANAGER']

with open(manager_file, 'r') as f:
    content = f.read()

replacements = [
    (
        r'(\.method\s+public\s+final\s+n\(Landroid/app/Activity;Z\)V)(.*?)(\.end method)',
        '''.method public final n(Landroid/app/Activity;Z)V
    .locals 2

    # Patched: Skip app-open/interstitial ad display flow
    iget-object v0, p0, Lcom/ants360/yicamera/base/l0;->j:Lcom/ants360/yicamera/base/l0$b;

    if-eqz v0, :cond_0

    const/4 v1, 0x1
    invoke-interface {v0, v1}, Lcom/ants360/yicamera/base/l0$b;->e(Z)V

    :cond_0
    return-void
.end method'''
    ),
    (
        r'(\.method\s+private\s+final\s+s\(Landroid/app/Activity;\)V)(.*?)(\.end method)',
        '''.method private final s(Landroid/app/Activity;)V
    .locals 0

    # Patched: Disable AppOpenAd show/load routine
    return-void
.end method'''
    ),
    (
        r'(\.method\s+private\s+final\s+t\(Landroid/app/Activity;I\)V)(.*?)(\.end method)',
        '''.method private final t(Landroid/app/Activity;I)V
    .locals 0

    # Patched: Disable Interstitial/AppOpen ad request routine
    return-void
.end method'''
    ),
    (
        r'(\.method\s+private\s+final\s+v\(Landroid/app/Activity;Z\)V)(.*?)(\.end method)',
        '''.method private final v(Landroid/app/Activity;Z)V
    .locals 2

    # Patched: Disable ad dispatch and immediately signal completion
    iget-object v0, p0, Lcom/ants360/yicamera/base/l0;->j:Lcom/ants360/yicamera/base/l0$b;

    if-eqz v0, :cond_0

    const/4 v1, 0x1
    invoke-interface {v0, v1}, Lcom/ants360/yicamera/base/l0$b;->e(Z)V

    :cond_0
    return-void
.end method'''
    ),
    (
        r'(\.method\s+public\s+final\s+r\(\)Z)(.*?)(\.end method)',
        '''.method public final r()Z
    .locals 1

    # Patched: Never report ready ads
    const/4 v0, 0x0
    return v0
.end method'''
    ),
]

patched = 0
for pattern, replacement in replacements:
    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern, replacement, content, count=1, flags=re.DOTALL)
        patched += 1
    else:
        print(f"Warning: Pattern not found: {pattern}")

with open(manager_file, 'w') as f:
    f.write(content)

print(f"l0 patching complete ({patched} methods patched)")
PYTHON_GOOGLE_AD_MANAGER
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
[ -n "$NATIVE_AD_UTIL" ] && echo "  8. NativeAdvertisingGoogleAdUtil - disables in-app ad entrypoints"
[ -n "$AD_DIALOG_ACTIVITY" ] && echo "  9. AdDialogFragment - skips ad dialog activity"
[ -n "$GOOGLE_AD_MANAGER" ] && echo " 10. l0 (GoogleAdManager) - disables app-open/interstitial flow"
