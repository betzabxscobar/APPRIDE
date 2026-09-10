# Reglas de R8 para la compilacion de publicacion.
#
# Flutter y sus plugins ya traen las suyas dentro de cada dependencia; aqui
# solo va lo que R8 no puede adivinar solo.

# El motor de Flutter se llama por JNI desde C++, asi que R8 no ve esas
# referencias y se lo llevaria por delante.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# `flutter_local_notifications` reconstruye los avisos programados leyendo
# clases por su nombre con Gson. Ofuscarlas rompe las notificaciones
# despues de reiniciar el telefono, y solo entonces: no se ve al probar.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Deja los numeros de linea en los informes de fallo. Sin esto, una traza de
# produccion no dice en que linea reventó.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter referencia Play Core para los "deferred components" —bajarse partes
# de la app despues de instalarla—. Ride no los usa, asi que esas clases no
# estan en el APK y R8 aborta diciendo que faltan. No falta nada: es codigo al
# que nunca se llega.
-dontwarn com.google.android.play.core.**
