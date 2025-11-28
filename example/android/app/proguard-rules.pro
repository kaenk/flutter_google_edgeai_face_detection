# ===============================
# 👇 MediaPipe / TFLite / AutoValue fix
# ===============================

-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**
-keep class javax.lang.model.** { *; }
-dontwarn javax.lang.model.**

-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

-keep class com.google.mediapipe.tasks.** { *; }
-dontwarn com.google.mediapipe.tasks.**

# 防止刪除 mediapipe 所需的反射類
-keepclassmembers class * {
    @com.google.mediapipe.** <fields>;
    @com.google.mediapipe.** <methods>;
}
