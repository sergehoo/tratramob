package com.tratra

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget d'accueil Tratra. Les données sont écrites par l'application (HomeWidget.saveWidgetData, voir
 * lib/services/home_widget_sync.dart) : uniquement des informations minimales et non sensibles. Déconnecté ou session expirée :
 * le widget invite à se connecter et n'affiche rien d'autre.
 */
class TratraWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tratra_widget)
            val signedIn = widgetData.getBoolean("tw_signed_in", false)
            if (!signedIn) {
                views.setTextViewText(R.id.widget_next, "Connectez-vous pour voir vos réservations et missions.")
                views.setViewVisibility(R.id.widget_counts, View.GONE)
                views.setViewVisibility(R.id.widget_status, View.GONE)
                views.setTextViewText(R.id.widget_updated, "")
            } else {
                views.setTextViewText(R.id.widget_next, widgetData.getString("tw_next", null) ?: "Aucune intervention prévue.")
                views.setViewVisibility(R.id.widget_counts, View.VISIBLE)
                views.setTextViewText(R.id.widget_missions, widgetData.getString("tw_missions", null) ?: "")
                views.setTextViewText(R.id.widget_unread, widgetData.getString("tw_unread", null) ?: "")
                val status = widgetData.getString("tw_status", null)
                views.setViewVisibility(R.id.widget_status, if (status.isNullOrEmpty()) View.GONE else View.VISIBLE)
                views.setTextViewText(R.id.widget_status, status ?: "")
                views.setTextViewText(R.id.widget_updated, widgetData.getString("tw_updated", null) ?: "")
            }
            views.setOnClickPendingIntent(R.id.widget_root, link(context, if (signedIn) "tratra://bookings" else "tratra://explore"))
            views.setOnClickPendingIntent(R.id.widget_action_request, link(context, "tratra://explore"))
            views.setOnClickPendingIntent(R.id.widget_action_messages, link(context, "tratra://messages"))
            views.setOnClickPendingIntent(R.id.widget_missions, link(context, "tratra://pro"))
            views.setOnClickPendingIntent(R.id.widget_unread, link(context, "tratra://notifications"))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun link(context: Context, uri: String) = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))
}
