package com.wtv.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.wtv.app.ui.WtvApp
import com.wtv.app.ui.theme.WtvTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WtvTheme {
                WtvApp()
            }
        }
    }
}
