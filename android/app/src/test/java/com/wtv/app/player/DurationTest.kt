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

    @Test fun `a press moves 10 seconds, a held key further the longer it is held`() {
        val len = 7_200_000L // 2 hours
        assertEquals(70_000L, scrubTo(60_000, len, forward = true, heldMs = 0))
        assertEquals(50_000L, scrubTo(60_000, len, forward = false, heldMs = 999))
        assertEquals(80_000L, scrubTo(60_000, len, forward = true, heldMs = 1_000))
        assertEquals(140_000L, scrubTo(60_000, len, forward = true, heldMs = 3_000))
        // No faster than 5 minutes a step, however long the key is held.
        assertEquals(360_000L, scrubTo(60_000, len, forward = true, heldMs = 5_000))
        assertEquals(360_000L, scrubTo(60_000, len, forward = true, heldMs = 600_000))
    }

    @Test fun `a step stays inside the video and short of its end`() {
        val len = 7_200_000L
        assertEquals(0L, scrubTo(4_000, len, forward = false, heldMs = 0))
        assertEquals(len - 5_000, scrubTo(len - 8_000, len, forward = true, heldMs = 0))
        // Already in the last 5 s: forward stays put rather than jumping back.
        assertEquals(len - 2_000, scrubTo(len - 2_000, len, forward = true, heldMs = 0))
        assertEquals(70_000L, scrubTo(60_000, null, forward = true, heldMs = 0))
    }
}
