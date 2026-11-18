package com.wtv.app.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OnNowTest {
    private val news = Programme("News", null, start = 1_000, end = 2_000)
    private val film = Programme("Film", null, start = 2_000, end = 5_000)

    @Test
    fun picksTheProgrammeRunningNow() {
        assertEquals(news, onAt(listOf(news, film), 1_500))
        // At the change-over the new programme is on.
        assertEquals(film, onAt(listOf(news, film), 2_000))
    }

    @Test
    fun nothingBeforeTheFirstOrAfterTheLast() {
        assertNull(onAt(listOf(news, film), 999))
        assertNull(onAt(listOf(news, film), 5_000))
        assertNull(onAt(emptyList(), 1_500))
    }
}
