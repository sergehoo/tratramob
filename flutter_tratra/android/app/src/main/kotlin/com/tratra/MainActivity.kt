package com.tratra

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Pays de la carte SIM (puis du réseau) pour présélectionner l'indicatif téléphonique. Aucune permission requise ;
        // aucun numéro n'est lu.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tratra/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "simCountry" -> result.success(simCountry())
                else -> result.notImplemented()
            }
        }
    }

    private fun simCountry(): String? = try {
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        listOf(tm?.simCountryIso, tm?.networkCountryIso).firstOrNull { !it.isNullOrBlank() && it.length == 2 }?.uppercase()
    } catch (e: Exception) {
        null
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
