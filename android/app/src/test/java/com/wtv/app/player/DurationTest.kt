package com.wtv.app.player

import org.junit.Assert.assertEquals
import org.junit.Test

class DurationTest {
    @Test fun `minutes and seconds under an hour, hours above`() {
        assertEquals("0:00", duration(0))
        assertEquals("0:59", duration(59_999))
        assertEquals("5:09", duration(309_000))
        assertEquals("1:00:00", duration(3_600_000))
        assertEquals("1:05:09", duration(3_909_000))
    }

    @Test fun `a negative time shows as zero`() {
        assertEquals("0:00", duration(-5_000))
    }

    @Test fun `a catch-up step stays inside the programme and short of its end`() {
        val len = 2_700_000L // 45 minutes
        assertEquals(30_000L, nextPosition(0, len, forward = true, held = false))
        assertEquals(120_000L, nextPosition(0, len, forward = true, held = true))
        assertEquals(0L, nextPosition(10_000, len, forward = false, held = false))
        assertEquals(len - 10_000, nextPosition(len - 30_000, len, forward = true, held = false))
        // Already in the last 10 s: forward stays put rather than jumping back.
        assertEquals(len - 4_000, nextPosition(len - 4_000, len, forward = true, held = false))
        assertEquals(90_000L, nextPosition(60_000, null, forward = true, held = false))
    }
}
