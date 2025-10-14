plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "com.example.vanillaebookreader"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.vanillaebookreader"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        externalNativeBuild {
            cmake {
                arguments("-DRUST_LIBRARY=ebook_reader")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

dependencies {
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.compose.material3:material3:1.2.1")
    implementation("androidx.compose.ui:ui:1.6.5")
}
