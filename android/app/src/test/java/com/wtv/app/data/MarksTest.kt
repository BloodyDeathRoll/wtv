package com.wtv.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarksTest {
    @Test fun `ratings read from the database words, and unknown ones are none`() {
        assertEquals(Rating.Love, rating("love"))
        assertEquals(Rating.Dislike, rating("dislike"))
        assertNull(rating("meh"))
        assertNull(rating(null))
    }

    @Test fun `the rating body names the card and the word`() {
        val body = JSONObject(ratingBody(42, Rating.Like))
        assertEquals(42, body.getInt("title_id"))
        assertEquals("like", body.getString("rating"))
        assertEquals(2, body.length())
    }
}
