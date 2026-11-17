package com.wtv.app.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class StreamUrlTest {
    private val login = ProviderLogin("provider.example:443/", "user", "p@ss word")

    @Test fun `movie, episode and live addresses, https by default, encoded credentials`() {
        assertEquals("https://provider.example:443/movie/user/p%40ss%20word/387982.mp4", streamUrl(login, StreamKind.Movie, 387982, "mp4"))
        assertEquals("https://provider.example:443/series/user/p%40ss%20word/369702.mkv", streamUrl(login, StreamKind.Episode, 369702, "mkv"))
        assertEquals("https://provider.example:443/live/user/p%40ss%20word/85956.ts", streamUrl(login, StreamKind.Live, 85956, null))
    }

    @Test fun `a server with a scheme keeps it`() {
        assertEquals("http://p.example/movie/u/p/1.mp4", streamUrl(ProviderLogin("http://p.example", "u", "p"), StreamKind.Movie, 1, null))
    }

    @Test fun `a path in the server is kept, any scheme case`() {
        assertEquals("https://p.example/xtream/movie/u/p/1.mkv", streamUrl(ProviderLogin("p.example/xtream/", "u", "p"), StreamKind.Movie, 1, "mkv"))
        assertEquals("HTTP://p.example/live/u/p/2.ts", streamUrl(ProviderLogin("HTTP://p.example", "u", "p"), StreamKind.Live, 2, null))
    }

    @Test fun `the password is sent exactly as saved, spaces included`() {
        assertEquals("https://p.example/movie/u/%20pw%20/1.mp4", streamUrl(ProviderLogin("p.example", " u ", " pw "), StreamKind.Movie, 1, null))
    }

    @Test fun `a login with an empty field is not complete`() {
        assertFalse(ProviderLogin("p.example", "u", " ").isComplete)
    }
}
