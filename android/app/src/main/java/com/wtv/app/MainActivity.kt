package com.wtv.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.wtv.app.ui.WtvApp
import com.wtv.app.ui.theme.WtvTheme

class MainActivity : ComponentActivity() {
    // An override, not a frozen copy of the configuration: other changes (font
    // scale, density) still reach the activity. The app has one activity; a
    // second one, or a service with text, needs the same.
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase)
        applyOverrideConfiguration(AppLanguage.override(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WtvTheme {
                WtvApp()
            }
        }
    }
}
