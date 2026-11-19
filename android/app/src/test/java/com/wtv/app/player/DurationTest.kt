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
}
