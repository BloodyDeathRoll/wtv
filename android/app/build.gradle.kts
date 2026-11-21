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
        versionCode = 5
        versionName = "0.5.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // The WTV database's public URL and publishable key (meant for apps;
        // row level security guards the data).
        buildConfigField("String", "SUPABASE_URL", "\"${setting("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_KEY", "\"${setting("SUPABASE_PUBLISHABLE_KEY")}\"")
        // WTW's database (read-only for us: the user's taste profile and ratings).
        buildConfigField("String", "WTW_SUPABASE_URL", "\"${setting("WTW_SUPABASE_URL")}\"")
        buildConfigField("String", "WTW_SUPABASE_KEY", "\"${setting("WTW_SUPABASE_ANON_KEY")}\"")
        // Google sign-in for TVs (device flow). Google treats this client's
        // secret as not confidential: it ships in every TV app.
        buildConfigField("String", "GOOGLE_TV_CLIENT_ID", "\"${setting("GOOGLE_TV_CLIENT_ID")}\"")
        buildConfigField("String", "GOOGLE_TV_CLIENT_SECRET", "\"${setting("GOOGLE_TV_CLIENT_SECRET")}\"")
    }

    // The release key lives outside the repo: WTV_KEYSTORE (absolute path),
    // WTV_KEYSTORE_PASSWORD and WTV_KEY_ALIAS in local.properties. Without it
    // the release build is unsigned and cannot be installed.
    val keystore = setting("WTV_KEYSTORE")
    if (keystore.isNotBlank()) {
        val store = file(keystore)
        require(store.exists()) { "WTV_KEYSTORE not found: $keystore" }
        signingConfigs.create("release") {
            storeFile = store
            storePassword = setting("WTV_KEYSTORE_PASSWORD")
            keyAlias = setting("WTV_KEY_ALIAS").ifBlank { "wtv" }
            keyPassword = setting("WTV_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        // Debug builds use the same key when it is present, so a test build installs
        // over the Play or sideloaded app on a TV without uninstalling (and losing its data).
        debug {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
        release {
            signingConfig = signingConfigs.findByName("release")
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
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
