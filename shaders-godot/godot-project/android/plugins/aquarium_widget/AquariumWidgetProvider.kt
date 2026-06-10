// AquariumWidgetProvider — Android home-screen widget for walstad loom.
//
// Reads the JSON snapshot the running game writes to user://widget_state.json
// (on Android that resolves to /data/data/<package>/files/widget_state.json),
// and renders the current tank stats: fish count, plant count, O2 %,
// ammonia, cycle phase, last named fish.
//
// Refresh contract:
//   - The widget refreshes on its android:updatePeriodMillis schedule (set
//     to 30 min in widget_info.xml — Android won't honour anything shorter
//     anyway since API 24).
//   - The widget ALSO refreshes when the game broadcasts an explicit
//     ACTION_AQUARIUM_TANK_UPDATED intent (sent by the Godot side after
//     each widget_state.json write — see the .gd plugin shim).
//
// If the JSON is missing (first launch, or game has never been opened on
// this device), the widget shows a "Tap to open" empty state.
//
// To wire this up:
//   1. Add to AndroidManifest.xml inside <application>:
//        <receiver android:name=".AquariumWidgetProvider"
//                  android:exported="true">
//          <intent-filter>
//            <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
//            <action android:name="com.mhsenkow.walstadloom.TANK_UPDATED"/>
//          </intent-filter>
//          <meta-data android:name="android.appwidget.provider"
//                     android:resource="@xml/widget_info"/>
//        </receiver>
//   2. Drop widget_info.xml into android/res/xml/.
//   3. Drop widget_layout.xml into android/res/layout/.
//   4. Build the Godot Android export with this plugin enabled.
//
// File layout assumed by the Godot side:
//   /data/data/<package>/files/widget_state.json
//   { "schema": 1, "updated_unix": 1700000000, "fish_count": 7, "o2_pct": 78,
//     "ammonia_ppm": "0.04", "cycle_phase": "cycled", ... }

package com.mhsenkow.walstadloom.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File

class AquariumWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TANK_UPDATED = "com.mhsenkow.walstadloom.TANK_UPDATED"
        private const val STATE_FILE = "widget_state.json"
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        for (id in ids) updateWidget(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TANK_UPDATED) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, AquariumWidgetProvider::class.java))
            for (id in ids) updateWidget(context, mgr, id)
        }
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_layout)
        val state = readState(context)
        if (state == null) {
            views.setTextViewText(R.id.widget_title, "Tap to open")
            views.setTextViewText(R.id.widget_subtitle, "your tank")
            views.setTextViewText(R.id.widget_stats, "")
        } else {
            val fish = state.optInt("fish_count", 0)
            val plants = state.optInt("plant_count", 0)
            val o2 = state.optInt("o2_pct", 0)
            val nh3 = state.optString("ammonia_ppm", "?")
            val phase = state.optString("cycle_phase", "")
            val last = state.optString("last_named_fish", "")
            views.setTextViewText(R.id.widget_title,
                if (last.isNotEmpty()) last else "your tank")
            views.setTextViewText(R.id.widget_subtitle, phase)
            views.setTextViewText(R.id.widget_stats,
                "$fish fish · $plants plants · O₂ $o2% · NH₃ $nh3")
        }
        // Tap-anywhere: open the main game activity.
        val openIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
        val pi = PendingIntent.getActivity(context, 0, openIntent,
            PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_root, pi)
        manager.updateAppWidget(id, views)
    }

    private fun readState(context: Context): JSONObject? {
        return try {
            val f = File(context.filesDir, STATE_FILE)
            if (!f.exists()) null else JSONObject(f.readText())
        } catch (_: Exception) {
            null
        }
    }
}
