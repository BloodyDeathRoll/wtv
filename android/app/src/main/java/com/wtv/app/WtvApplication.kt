package com.wtv.app

import android.app.Application
import com.wtv.app.data.Api
import com.wtv.app.data.Catalog
import com.wtv.app.data.Session
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** Holds the app-wide services. */
class WtvApplication : Application() {
    val http by lazy { OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build() }
    val catalog by lazy { Catalog(Api(Session(this, http), http)) }
}
