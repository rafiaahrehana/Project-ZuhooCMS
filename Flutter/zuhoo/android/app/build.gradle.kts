plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json and generates the resources
    // firebase_core needs at runtime — must be applied in the app module.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.cms.zuhoo"
    // Pinned rather than inherited from `flutter.compileSdkVersion` (36 at the
    // time of writing): flutter_secure_storage 11 ships AAR metadata requiring
    // its consumers to compile against 37. Raising compileSdk only widens the
    // APIs available at compile time — targetSdk below still governs runtime
    // behaviour, and minSdk still governs which devices can install this.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires this to be on.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cms.zuhoo"
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

dependencies {
    // Paired with `isCoreLibraryDesugaringEnabled` above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
