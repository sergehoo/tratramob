package com.tratra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Messages FCM « Tratra Flash » (messages de DONNÉES, priorité haute), reçus même application fermée :
 *  - t = new_mission  : affiche l'alerte (actions Accepter / Refuser / Voir, compte à rebours, retrait à l'échéance) — sauf si
 *    l'application est au premier plan : l'écran Tratra Flash prend alors le relais (aucun son en double) ;
 *  - t = flash_closed : retire l'alerte (mission attribuée à quelqu'un d'autre, expirée ou annulée).
 * Même diffusion que le récepteur du plugin firebase_messaging (les deux reçoivent le message ; aucun ne l'interrompt).
 */
class FlashMessageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        // Message de NOTIFICATION (ancien format) : affiché par Firebase lui-même ; ne jamais l'afficher deux fois.
        if (extras.containsKey("gcm.notification.title") || extras.containsKey("gcm.n.e")) return
        when (extras.getString("t")) {
            "new_mission" -> {
                if (TratraAlerts.appVisible) return
                val data = extras.keySet()
                    .filter { !it.startsWith("google.") && !it.startsWith("gcm.") && it != "from" && it != "collapse_key" }
                    .mapNotNull { key -> extras.get(key)?.let { key to it.toString() } }
                    .toMap()
                val sentAt = when (val v = extras.get("google.sent_time")) {
                    is Long -> v
                    is String -> v.toLongOrNull() ?: 0L
                    else -> 0L
                }
                TratraAlerts.showOffer(context.applicationContext, data, sentAt)
            }
            "flash_closed" -> extras.getString("offer")?.toIntOrNull()?.let { TratraAlerts.cancel(context.applicationContext, it) }
        }
    }
}
