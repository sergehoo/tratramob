package com.tratra

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * Canal des notifications push (FCM). Le serveur le désigne par son identifiant (`tratra_default`) :
     * importance haute pour que « votre artisan est en route / est arrivé » s'affiche immédiatement.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "tratra_default",
            "Réservations et suivi",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Statut des réservations, arrivée de l'artisan et messages."
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
