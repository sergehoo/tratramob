package com.tratra

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Canaux des notifications push (FCM). Le serveur désigne le canal par son identifiant selon la catégorie :
     *  - tratra_default       : réservations, messages, suivi, paiements, compte (importance haute, alerte immédiate) ;
     *  - tratra_updates       : avis, entreprise, informations (importance normale) ;
     *  - tratra_announcements : annonces (importance normale, coupables séparément dans les réglages Android).
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel("tratra_default", "Réservations et suivi", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Statut des réservations, arrivée de l'artisan, messages et paiements."
            }
        )
        manager.createNotificationChannel(
            NotificationChannel("tratra_updates", "Avis et informations", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Nouveaux avis, activité de votre entreprise et informations de service."
            }
        )
        manager.createNotificationChannel(
            NotificationChannel("tratra_announcements", "Annonces", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Annonces et nouveautés de Tratra."
            }
        )
    }
}
