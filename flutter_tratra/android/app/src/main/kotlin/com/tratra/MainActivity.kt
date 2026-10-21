package com.tratra

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var flashChannel: MethodChannel? = null
    /** Action d'une alerte Tratra Flash reçue avant que Dart n'écoute : remise à Dart dès qu'il la demande (une seule fois). */
    private var pendingFlashAction: Map<String, Any>? = null
    /** Dart a demandé l'action de lancement : il écoute désormais « onAction ». Faux après une recréation de l'activité
     *  (processus arrêté : Android recrée l'activité puis lui remet l'action par onNewIntent, AVANT que Dart ne tourne). */
    private var dartReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        TratraAlerts.ensureChannels(this)
        handleFlashIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleFlashIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        TratraAlerts.appVisible = true
    }

    override fun onPause() {
        TratraAlerts.appVisible = false
        super.onPause()
    }

    /** Accepter / Refuser / Voir touché sur l'alerte : l'alerte s'arrête aussitôt, l'application exécute l'action (session authentifiée). */
    private fun handleFlashIntent(intent: Intent?) {
        val action = intent?.getStringExtra(TratraAlerts.EXTRA_ACTION) ?: return
        val offer = intent.getIntExtra(TratraAlerts.EXTRA_OFFER, 0)
        intent.removeExtra(TratraAlerts.EXTRA_ACTION)
        if (offer <= 0) return
        TratraAlerts.cancel(this, offer)
        val payload = mapOf("action" to action, "offer" to offer)
        val channel = flashChannel
        if (dartReady && channel != null) {
            channel.invokeMethod("onAction", payload)
        } else {
            pendingFlashAction = payload
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flashChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tratra/flash").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchAction" -> {
                        dartReady = true
                        result.success(pendingFlashAction)
                        pendingFlashAction = null
                    }
                    "getPrefs" -> result.success(mapOf(
                        "sound" to TratraAlerts.soundEnabled(this@MainActivity),
                        "vibration" to TratraAlerts.vibrationEnabled(this@MainActivity)))
                    "setPrefs" -> {
                        TratraAlerts.setPrefs(this@MainActivity, call.argument<Boolean>("sound") ?: true,
                            call.argument<Boolean>("vibration") ?: true)
                        result.success(true)
                    }
                    "play" -> result.success(TratraAlerts.play(this@MainActivity, call.argument<String>("sound") ?: "tratra_flash",
                        call.argument<Boolean>("withSound") ?: true, call.argument<Boolean>("withVibration") ?: true))
                    "stop" -> {
                        TratraAlerts.stop(this@MainActivity)
                        result.success(true)
                    }
                    "cancel" -> {
                        call.argument<Int>("offer")?.let { TratraAlerts.cancel(this@MainActivity, it) }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
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
}
