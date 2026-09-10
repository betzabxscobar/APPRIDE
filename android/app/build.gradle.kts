import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Datos del keystore de publicacion. `key.properties` NO entra en el
// repositorio —lleva las contrasenas del almacen— y por eso el fichero puede
// no existir: en ese caso se compila con la firma de depuracion, que sirve
// para probar entre nosotros pero no para publicar.
// Ver docs/PUBLICAR.md.
val firmaProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hayFirmaPropia = firmaProps.getProperty("storeFile") != null

android {
    namespace = "com.example.ride"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Lo pide `flutter_local_notifications`: usa clases de fecha y hora de
        // Java 8 que no existen en los Android viejos, y el desugaring las
        // traduce al compilar. Sin esto la compilacion falla en
        // checkReleaseAarMetadata.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // El identificador con el que Play Store conoce la app. NO se puede
        // cambiar despues de publicar: una app con otro applicationId es otra
        // app distinta, sin actualizaciones ni reseñas ni instalaciones.
        // Venia como `com.example.ride`, que Play Store rechaza por ser el de
        // ejemplo de Flutter.
        applicationId = "com.rideviajes.ride"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("publicacion") {
            if (hayFirmaPropia) {
                keyAlias = firmaProps.getProperty("keyAlias")
                keyPassword = firmaProps.getProperty("keyPassword")
                storeFile = file(firmaProps.getProperty("storeFile"))
                storePassword = firmaProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Con `key.properties` se firma de verdad; sin el, con la clave de
            // depuracion, que es lo que hace falta para `flutter run --release`
            // y para repartir APKs de prueba. Una firmada en depuracion NO se
            // puede subir a Play Store, y ademas no deja actualizar encima de
            // una firmada de verdad: hay que desinstalar.
            signingConfig = if (hayFirmaPropia) {
                signingConfigs.getByName("publicacion")
            } else {
                signingConfigs.getByName("debug")
            }

            // Quita el codigo y los recursos que nadie usa, y ofusca los
            // nombres. Baja el peso del APK y deja el codigo menos legible al
            // descompilarlo. `shrinkResources` exige `isMinifyEnabled`.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
