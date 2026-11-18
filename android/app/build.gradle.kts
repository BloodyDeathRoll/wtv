import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/** From local.properties (developer machines) or the environment (CI); empty if neither. */
val localProperties = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
fun setting(name: String): String = localProperties.getProperty(name) ?: System.getenv(name) ?: ""

android {
    // Media3's track classes call android.text.TextUtils; the stub returns defaults instead of throwing.
    testOptions.unitTests.isReturnDefaultValues = true
    namespace = "com.wtv.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.wtv.app"
        minSdk = 26
        // Behind compileSdk on purpose: the app has only been run on API 36.
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        // The WTV database's public URL and publishable key (meant for apps;
        // row level security guards the data).
        buildConfigField("String", "SUPABASE_URL", "\"${setting("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_KEY", "\"${setting("SUPABASE_PUBLISHABLE_KEY")}\"")
    }

    buildTypes {
        release {
            // Drops unused code, e.g. most of the Material icon set.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.tv.material)
    implementation(libs.androidx.material.icons)
    implementation(libs.coil.compose)
    implementation(libs.coil.network)
    implementation(libs.okhttp)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    testImplementation(libs.junit)
    testImplementation(libs.org.json)
}
