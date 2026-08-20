import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hexadigitall.makaw"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hexadigitall.makaw"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    val signingEnabled = keystorePropertiesFile.exists()
    if (signingEnabled) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    if (signingEnabled) {
        signingConfigs {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                @Suppress("DEPRECATION")
                isV1SigningEnabled = true
                @Suppress("DEPRECATION")
                isV2SigningEnabled = true
            }
        }
    }

    buildTypes {
        release {
            if (signingEnabled) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    applicationVariants.all {
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            val abi = if (outputFileName.contains("arm64")) "arm64"
                      else if (outputFileName.contains("armeabi")) "arm"
                      else if (outputFileName.contains("x86_64")) "x86_64"
                      else "universal"
            output.outputFileName = "makaw-${versionName}-${abi}.apk"
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
