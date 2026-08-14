plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // applicationId/namespace fijados por el CEO: com.turnariopro.app (misma app "Turnario" ya
    // creada en Google Play Developer, ver proyectos/turnos-profesionales/08-despliegue/
    // google-play-billing.md §3.2) — NO usar el valor por default que arma `flutter create
    // --org com.turnariopro .` (org + `name` de pubspec.yaml = com.turnariopro.turnos_profesionales).
    namespace = "com.turnariopro.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Ver comentario de `namespace` arriba — mismo valor, no negociable (google-play-billing.md §3.2).
        applicationId = "com.turnariopro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
