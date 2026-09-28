# google_mlkit_text_recognition 0.17.1 compiles optional script branches but
# includes only the Latin ML Kit dependency at runtime. The cellar scanner
# always requests TextRecognitionScript.latin. Suppress R8's missing-class
# diagnostics for the four unused modules; add their dependencies if the app
# ever enables those scripts.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
