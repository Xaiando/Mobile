# google_mlkit_text_recognition 0.17.1 compiles optional script branches but
# includes only the Latin ML Kit dependency at runtime. The cellar scanner
# always requests TextRecognitionScript.latin. Suppress R8's missing-class
# diagnostics for the four unused modules; add their dependencies if the app
# ever enables those scripts.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# R8's full mode, the default since Android Gradle plugin 8, no longer keeps
# the default constructor of a class that a rule keeps without naming one. ML
# Kit creates its component registrars by reflection: ComponentDiscovery calls
# getDeclaredConstructor() on each class the manifest names. With the
# constructors gone, every registrar fails to start, and text recognition then
# throws a NullPointerException in release builds only. Debug builds are not
# shrunk, so only tool/android/ocr_smoke.sh on a release build shows it.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
