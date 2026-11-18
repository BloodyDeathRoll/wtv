package com.wtv.app

import android.app.Application
import com.wtv.app.data.Api
import com.wtv.app.data.Catalog
import com.wtv.app.data.GoogleSignIn
import com.wtv.app.data.Session
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** Holds the app-wide services. */
class WtvApplication : Application() {
    val http by lazy { OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build() }
    val session by lazy { Session(this, http) }
    // WTW is read-only for us: its session is used only to read the user's taste profile and ratings.
    val wtw by lazy { Session(this, http, "wtw_session", BuildConfig.WTW_SUPABASE_URL, BuildConfig.WTW_SUPABASE_KEY, anonymous = false) }
    val google by lazy { GoogleSignIn(http) }
    val catalog by lazy { Catalog(Api(session, http)) }
}
