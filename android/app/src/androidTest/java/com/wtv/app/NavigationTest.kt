package com.wtv.app

import android.view.KeyEvent
import android.view.View
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The remote's Back and focus rules in `ui/WtvApp.kt`, driven with real key
 * presses. They hold whether the page underneath shows the catalog or, in a
 * build without database settings (CI), the error page with Retry.
 */
@RunWith(AndroidJUnit4::class)
class NavigationTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()

    private fun text(id: Int) = rule.activity.getString(id)

    // The app may run in Hebrew, where the tabs run right to left.
    private val forward get() =
        if (rule.activity.resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL) KeyEvent.KEYCODE_DPAD_LEFT
        else KeyEvent.KEYCODE_DPAD_RIGHT

    private fun press(code: Int) {
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(code)
        rule.waitForIdle()
    }

    private fun tab(id: Int) = hasText(text(id))
    private val anyTab get() = listOf(R.string.tab_home, R.string.tab_movies, R.string.tab_series, R.string.tab_live).map(::tab).reduce { a, b -> a or b }
    private val anyRailItem get() =
        listOf(R.string.rail_search, R.string.rail_categories, R.string.rail_watchlist, R.string.rail_settings)
            .map { hasContentDescription(text(it)) }.reduce { a, b -> a or b }

    private fun waitFor(matcher: SemanticsMatcher, timeoutMs: Long = 20_000) =
        rule.waitUntil(timeoutMs) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    /** Waits for the tab to hold the focus, then for the page under it to have something to focus. */
    private fun startOn(tabId: Int) {
        waitFor(tab(R.string.tab_home) and isFocused())
        if (tabId == R.string.tab_movies) press(forward)
        waitFor(tab(tabId) and isFocused())
        waitFor(hasClickAction() and !anyTab and !anyRailItem)
    }

    @Test
    fun downFromTabEntersPageAndUpReturnsToIt() {
        // Home: right after a tab switch the old section's cards are still there to wait on.
        startOn(R.string.tab_home)
        press(KeyEvent.KEYCODE_DPAD_DOWN)
        waitFor(isFocused() and !anyTab and !anyRailItem)
        press(KeyEvent.KEYCODE_DPAD_UP)
        waitFor(tab(R.string.tab_home) and isFocused())
    }

    @Test
    fun backFromPageFocusesSelectedTab() {
        startOn(R.string.tab_movies)
        press(KeyEvent.KEYCODE_DPAD_DOWN)
        waitFor(isFocused() and !anyTab and !anyRailItem)
        press(KeyEvent.KEYCODE_BACK)
        // The selected tab, not the first one: focusing Home would switch the section.
        waitFor(tab(R.string.tab_movies) and isFocused())
    }

    @Test
    fun backOnTabsLeavesTheApp() {
        startOn(R.string.tab_home)
        val activity = rule.activity
        press(KeyEvent.KEYCODE_BACK)
        assertTrue("Back on the tabs should leave the app", activity.isFinishing || activity.isDestroyed)
    }

    @Test
    fun railPageClosesOnBackAndSurvivesRecreation() {
        startOn(R.string.tab_home)
        val categories = text(R.string.rail_categories)
        // TV buttons ignore touch, so the click goes through the accessibility action.
        rule.onNodeWithContentDescription(categories).performSemanticsAction(SemanticsActions.OnClick)
        waitFor(hasText(categories))
        rule.activityRule.scenario.recreate()
        waitFor(hasText(categories))
        press(KeyEvent.KEYCODE_BACK)
        rule.waitUntil(5_000) { rule.onAllNodes(hasText(categories)).fetchSemanticsNodes().isEmpty() }
    }
}
