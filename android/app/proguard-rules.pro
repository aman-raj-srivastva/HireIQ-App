# Keep PDFBox core classes
-keep class com.tom_roush.pdfbox.** { *; }
-keep class org.bouncycastle.** { *; }

# Explicitly exclude JP2 filter classes
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# Keep any classes referenced by PDFBox
-keep class * implements com.tom_roush.pdfbox.filter.Filter { *; }
-keep class * implements com.tom_roush.pdfbox.pdmodel.PDDocumentInformation { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep PDFBox's internal classes
-keep class com.tom_roush.pdfbox.io.** { *; }
-keep class com.tom_roush.pdfbox.pdmodel.** { *; }
-keep class com.tom_roush.pdfbox.rendering.** { *; }
-keep class com.tom_roush.pdfbox.util.** { *; }

# Keep any custom PDF-related classes in your app
-keep class com.aicon.hireiq.** { *; }

# Keep any classes that might be used by PDFBox through reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses 