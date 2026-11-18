package com.wtv.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class GoogleSignInTest {
    @Test
    fun readsEachGoogleAnswer() {
        assertEquals(Poll.Token("abc"), pollResult(200, JSONObject("""{"id_token":"abc","access_token":"x"}""")))
        assertEquals(Poll.Pending, pollResult(428, JSONObject("""{"error":"authorization_pending"}""")))
        assertEquals(Poll.SlowDown, pollResult(403, JSONObject("""{"error":"slow_down"}""")))
        assertEquals(Poll.Failed("Sign-in was declined on the phone"), pollResult(403, JSONObject("""{"error":"access_denied"}""")))
        assertEquals(Poll.Failed("The code expired"), pollResult(400, JSONObject("""{"error":"expired_token"}""")))
        // A success without an ID token (no openid scope) is a failure, not a token.
        assertEquals(Poll.Failed("Google sign-in failed (HTTP 200)"), pollResult(200, JSONObject("""{"access_token":"x"}""")))
    }
}
