#!/usr/bin/env python3
"""يُشغَّل بعد `flutter create` لتهيئة مشروع Android: صلاحيات الإشعارات
ومستقبلاتها وتمكين core library desugaring المطلوب لإشعارات Flutter."""
import pathlib
import re
import sys

app = pathlib.Path('android/app')
manifest = app / 'src/main/AndroidManifest.xml'
if not manifest.exists():
    sys.exit('AndroidManifest.xml not found; run flutter create first')

m = manifest.read_text(encoding='utf-8')
perms = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
]
add = ''.join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
if add:
    m = m.replace('<application', add + '    <application', 1)

receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
if 'ScheduledNotificationReceiver' not in m:
    m = m.replace('</application>', receivers + '    </application>', 1)
manifest.write_text(m, encoding='utf-8')

DESUGAR = '2.1.5'
kts = app / 'build.gradle.kts'
groovy = app / 'build.gradle'
if kts.exists():
    g = kts.read_text(encoding='utf-8')
    if 'isCoreLibraryDesugaringEnabled' not in g:
        if 'compileOptions {' in g:
            g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        else:
            g = re.sub(r'android\s*\{', 'android {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }', g, count=1)
    if 'coreLibraryDesugaring(' not in g:
        g += f'\ndependencies {{\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR}")\n}}\n'
    kts.write_text(g, encoding='utf-8')
elif groovy.exists():
    g = groovy.read_text(encoding='utf-8')
    if 'coreLibraryDesugaringEnabled' not in g:
        if 'compileOptions {' in g:
            g = g.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        else:
            g = re.sub(r'android\s*\{', 'android {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }', g, count=1)
    if 'coreLibraryDesugaring ' not in g:
        g += f"\ndependencies {{\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:{DESUGAR}'\n}}\n"
    groovy.write_text(g, encoding='utf-8')
else:
    sys.exit('app/build.gradle(.kts) not found')
print('Android project patched')
