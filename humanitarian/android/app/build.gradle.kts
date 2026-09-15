plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties
import java.io.FileInputStream

// Release signing material, kept out of git (see android/.gitignore). When the
// file is absent — a fresh clone, or CI without the secret — the release
// signingConfig is simply not created and a release build fails loudly rather
// than silently falling back to the debug key, which is how a debug-signed
// artifact reaches a store in the first place.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.easytech.humanitarian"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.easytech.humanitarian"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the upload key, not the debug key. Play refuses a
            // debug-signed upload, and the debug key is shared by every
            // developer machine — it is not an identity worth shipping under.
            //
            // The keystore and its passwords live in android/key.properties and
            // android/upload-keystore.jks, both gitignored. LOSING THAT FILE
            // MEANS THE APP CAN NEVER BE UPDATED ON PLAY under this identity,
            // so it belongs in a password manager, not only on one laptop.
            //
            // findByName, not getByName: Gradle configures EVERY build type on
            // every build, so getByName threw "SigningConfig with name 'release'
            // not found" for a plain debug build in any checkout without
            // key.properties (a fresh clone, a git worktree). The loud,
            // release-only failure is kept by the task-graph check below.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// A release build without the signing material must still fail loudly (see the
// comment on keystoreProperties above), and say what is missing. The check
// fires for any build whose task graph includes this app's release-variant
// tasks — assembleRelease and bundleRelease (flutter build apk/appbundle), and
// also :app:test and :app:check, which pull release tasks in; that errs on the
// safe side. Debug and profile builds sign with the debug key and need no
// secrets, so they keep working in a checkout without key.properties.
//
// It asks whether the release build type actually has a signing config, not
// whether key.properties exists, so it stays right if signing ever moves to
// another source.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project && task.name.contains("Release")
    }
    val releaseSigning = android.buildTypes.getByName("release").signingConfig
    if (buildsRelease && releaseSigning == null) {
        throw GradleException(
            "No release signing config: android/key.properties is missing, so " +
                "this release build cannot be signed with the upload key. Put " +
                "key.properties and the keystore it names back in android/ " +
                "(see the comment above buildTypes.release).",
        )
    }
}

flutter {
    source = "../.."
}
