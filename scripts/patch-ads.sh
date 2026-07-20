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
echo "See docs/ad-removal.md for how each patch was derived."

# Track failures of CORE ad patches so CI breaks loudly on the next app update
# instead of silently shipping an APK that still has ads.
CORE_FAILURES=0

# Resolve a class by its Kotlin/Java .source name (survives obfuscation renames
# of the class letter). Picks the top-level class file (no '$' inner classes).
find_by_source() {
    local source_name="$1"
    grep -rl "\.source \"${source_name}\"" "$DECOMPILED_DIR"/smali* 2>/dev/null \
        | grep -v '\$' | head -1
}

# ---------------------------------------------------------------------------
# 1. Splash ads -- SplashActivity.L2()
#    L2() is the splash-ad orchestrator; force it to run the app's own no-ad
#    path (K2(true) + O2()), which skips every splash network at once.
# ---------------------------------------------------------------------------
echo ""
echo ">>> [core] Splash ads: SplashActivity.L2()"
SPLASH_ACTIVITY=$(find "$DECOMPILED_DIR" -name "SplashActivity.smali" -path "*/com/ants360/yicamera/activity/*" | head -1)

if [ -z "$SPLASH_ACTIVITY" ]; then
    echo "ERROR: SplashActivity.smali not found"
    CORE_FAILURES=$((CORE_FAILURES + 1))
else
    echo "Found: $SPLASH_ACTIVITY"
    SPLASH_ACTIVITY="$SPLASH_ACTIVITY" python3 << 'PY'
import os, re, sys

path = os.environ['SPLASH_ACTIVITY']
with open(path) as f:
    content = f.read()

pattern = r'\.method private final L2\(\)V.*?\.end method'
replacement = '''.method private final L2()V
    .locals 1

    # Patched: skip all splash ad networks; run the app's native no-ad path
    const/4 v0, 0x1

    invoke-direct {p0, v0}, Lcom/ants360/yicamera/activity/SplashActivity;->K2(Z)V

    invoke-direct {p0}, Lcom/ants360/yicamera/activity/SplashActivity;->O2()V

    return-void
.end method'''

if not re.search(pattern, content, re.DOTALL):
    print("ERROR: L2() not found -- splash-ad orchestrator moved")
    sys.exit(3)

# Sanity: the no-ad path methods we jump to must still exist.
for m in ('K2(Z)V', 'O2()V'):
    if m not in content:
        print(f"ERROR: expected no-ad-path method {m} missing")
        sys.exit(3)

content = re.sub(pattern, replacement, content, count=1, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
print("Patched L2() -- all splash networks bypassed")
PY
    [ $? -ne 0 ] && CORE_FAILURES=$((CORE_FAILURES + 1))
fi

# ---------------------------------------------------------------------------
# 2. In-app banner / native ads -- pb/o.a() (UnderViewManager)
#    Every banner/native display method in the ad util gates on this boolean and
#    returns early (no ad) when it is true. Force it true everywhere.
# ---------------------------------------------------------------------------
echo ""
echo ">>> [core] In-app native/banner ads: UnderViewManager.a()"
UNDER_VIEW=$(find_by_source "UnderViewManager.kt")

if [ -z "$UNDER_VIEW" ]; then
    echo "ERROR: UnderViewManager.kt not found"
    CORE_FAILURES=$((CORE_FAILURES + 1))
else
    echo "Found: $UNDER_VIEW"
    UNDER_VIEW="$UNDER_VIEW" python3 << 'PY'
import os, re, sys

path = os.environ['UNDER_VIEW']
with open(path) as f:
    content = f.read()

pattern = r'\.method public a\(\)Z.*?\.end method'
replacement = '''.method public a()Z
    .locals 1

    # Patched: force the ad-suppression gate ON -> no in-app native/banner ads
    const/4 v0, 0x1

    return v0
.end method'''

if not re.search(pattern, content, re.DOTALL):
    print("ERROR: a()Z not found in UnderViewManager")
    sys.exit(3)

content = re.sub(pattern, replacement, content, count=1, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
print("Patched a() -> true -- all in-app banner/native placements suppressed")
PY
    [ $? -ne 0 ] && CORE_FAILURES=$((CORE_FAILURES + 1))
fi

# ---------------------------------------------------------------------------
# 3. App-open / interstitial / resume ads -- l0 (GoogleAdManager)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [core] App-open/interstitial/resume ads: GoogleAdManager"
GOOGLE_AD_MANAGER=$(find_by_source "GoogleAdManager.kt")

if [ -z "$GOOGLE_AD_MANAGER" ]; then
    echo "ERROR: GoogleAdManager.kt not found"
    CORE_FAILURES=$((CORE_FAILURES + 1))
else
    echo "Found: $GOOGLE_AD_MANAGER"
    GOOGLE_AD_MANAGER="$GOOGLE_AD_MANAGER" python3 << 'PY'
import os, re, sys

path = os.environ['GOOGLE_AD_MANAGER']
with open(path) as f:
    content = f.read()

# The class name letter (l0) can change; derive it from the class header so the
# self-referencing callback code stays correct.
m = re.search(r'\.class[^\n]*\bL([^;]+);', content)
if not m:
    print("ERROR: could not read class descriptor")
    sys.exit(3)
cls = m.group(1)

# Signal the completion callback (l0$b.e(true)) then return -- so anything
# waiting on the ad to finish proceeds immediately.
signal_complete = f'''    iget-object v0, p0, L{cls};->j:L{cls}$b;

    if-eqz v0, :cond_0

    const/4 v1, 0x1

    invoke-interface {{v0, v1}}, L{cls}$b;->e(Z)V

    :cond_0
    return-void'''

replacements = [
    # n(Activity,Z): dispatch app-open/interstitial -> signal complete, no ad
    (r'\.method public final n\(Landroid/app/Activity;Z\)V.*?\.end method',
     f'''.method public final n(Landroid/app/Activity;Z)V
    .locals 2

    # Patched: skip app-open/interstitial display; signal completion
{signal_complete}
.end method'''),
    # v(Activity,Z): dispatch -> signal complete, no ad
    (r'\.method private final v\(Landroid/app/Activity;Z\)V.*?\.end method',
     f'''.method private final v(Landroid/app/Activity;Z)V
    .locals 2

    # Patched: disable ad dispatch; signal completion
{signal_complete}
.end method'''),
    # s(Activity): load/show AppOpenAd -> no-op
    (r'\.method private final s\(Landroid/app/Activity;\)V.*?\.end method',
     '''.method private final s(Landroid/app/Activity;)V
    .locals 0

    # Patched: disable AppOpenAd show/load
    return-void
.end method'''),
    # t(Activity,I): request Interstitial/AppOpen -> no-op
    (r'\.method private final t\(Landroid/app/Activity;I\)V.*?\.end method',
     '''.method private final t(Landroid/app/Activity;I)V
    .locals 0

    # Patched: disable Interstitial/AppOpen request
    return-void
.end method'''),
    # o(): show app-open ad on resume -> never show
    (r'\.method public final o\(\)Z.*?\.end method',
     '''.method public final o()Z
    .locals 1

    # Patched: never show the resume app-open ad
    const/4 v0, 0x0

    return v0
.end method'''),
    # r(): "ad ready" -> always false
    (r'\.method public final r\(\)Z.*?\.end method',
     '''.method public final r()Z
    .locals 1

    # Patched: never report a ready ad
    const/4 v0, 0x0

    return v0
.end method'''),
]

patched = 0
for pat, repl in replacements:
    if re.search(pat, content, re.DOTALL):
        content = re.sub(pat, repl, content, count=1, flags=re.DOTALL)
        patched += 1
    else:
        print(f"ERROR: GoogleAdManager pattern not found: {pat[:60]}...")

with open(path, 'w') as f:
    f.write(content)

print(f"Patched GoogleAdManager ({patched}/{len(replacements)} methods)")
if patched != len(replacements):
    sys.exit(3)
PY
    [ $? -ne 0 ] && CORE_FAILURES=$((CORE_FAILURES + 1))
fi

# ---------------------------------------------------------------------------
# 4. Cloud / AI upsell popups (best-effort: warn on miss, never fail the build)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [best-effort] Cloud / AI upsell popups"

# 4a. Dialog fragments -- dismiss immediately.
patch_dialog_dismiss() {
    local name="$1" method_sig="$2" super_hint="$3"
    local file
    file=$(find "$DECOMPILED_DIR" -name "$name.smali" | head -1)
    if [ -z "$file" ]; then
        echo "  (skip) $name not found"
        return
    fi
    FILE="$file" METHOD="$method_sig" python3 << 'PY'
import os, re
path = os.environ['FILE']
method = os.environ['METHOD']
with open(path) as f:
    content = f.read()

# Insert a dismiss()+return right after the method's `.locals` line.
pattern = rf'(\.method\s+public\s+{re.escape(method)}.*?\.locals\s+\d+)'
m = re.search(pattern, content, re.DOTALL)
if not m:
    print(f"  (warn) {os.path.basename(path)}: {method} not found")
    raise SystemExit(0)

inject = m.group(1) + '''

    # Patched: dismiss upsell popup immediately
    invoke-virtual {p0}, Landroidx/fragment/app/DialogFragment;->dismiss()V

    return-void'''
content = content.replace(m.group(1), inject, 1)
with open(path, 'w') as f:
    f.write(content)
print(f"  Patched {os.path.basename(path)} {method}")
PY
}

patch_dialog_dismiss "FreeCloudDialogFragment" "onViewCreated(Landroid/view/View;Landroid/os/Bundle;)V"
patch_dialog_dismiss "SmartAIPurchaseDialog"   "onCreate(Landroid/os/Bundle;)V"

# 4b. Activities -- finish immediately after super.onCreate.
patch_activity_finish() {
    local name="$1"
    local file
    file=$(find "$DECOMPILED_DIR" -name "$name.smali" | head -1)
    if [ -z "$file" ]; then
        echo "  (skip) $name not found"
        return
    fi
    FILE="$file" python3 << 'PY'
import os, re
path = os.environ['FILE']
with open(path) as f:
    content = f.read()

pattern = (r'(\.method\s+(?:public|protected)\s+onCreate\(Landroid/os/Bundle;\)V'
           r'.*?invoke-super\s+\{[^}]+\},\s*L[^;]+;->onCreate\(Landroid/os/Bundle;\)V)')
m = re.search(pattern, content, re.DOTALL)
if not m:
    print(f"  (warn) {os.path.basename(path)}: onCreate not found")
    raise SystemExit(0)

inject = m.group(1) + '''

    # Patched: skip upsell/ad screen -- finish immediately
    invoke-virtual {p0}, Landroid/app/Activity;->finish()V

    return-void'''
content = content.replace(m.group(1), inject, 1)
with open(path, 'w') as f:
    f.write(content)
print(f"  Patched {os.path.basename(path)} onCreate")
PY
}

patch_activity_finish "CloudIntroductionsActivity"
patch_activity_finish "NoCloudIntroductionsActivity"
patch_activity_finish "CloudFeaturesActivity"
patch_activity_finish "AdDialogFragment"

# ---------------------------------------------------------------------------
echo ""
echo "=== Patching Complete ==="
echo "Core ad surfaces:"
echo "  1. SplashActivity.L2()   - all splash networks bypassed"
echo "  2. UnderViewManager.a()  - all in-app banner/native ads suppressed"
echo "  3. GoogleAdManager       - app-open/interstitial/resume ads disabled"
echo "Best-effort: cloud & AI upsell popups auto-dismissed/finished."

if [ "$CORE_FAILURES" -ne 0 ]; then
    echo ""
    echo "FATAL: $CORE_FAILURES core ad patch(es) failed to apply."
    echo "The app format changed -- see docs/ad-removal.md 'Playbook' and fix the anchors."
    exit 1
fi
