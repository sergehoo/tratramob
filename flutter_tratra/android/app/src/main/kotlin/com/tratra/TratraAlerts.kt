package com.tratra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Canaux de notification et alerte Tratra Flash (sonnerie « Pulse »).
 *
 *  - tratra_activity       : réservations, messages, suivi, paiements, compte (importance haute, son « tratra_notification »).
 *  - tratra_updates        : avis, entreprise, informations (importance normale).
 *  - tratra_announcements  : annonces (importance normale).
 *  - tratra_new_missions*  : nouvelles missions (importance haute, son « tratra_flash », vibration rythmée). Un canal Android fige son
 *    son et sa vibration à sa création : les réglages « Son » / « Vibration » de l'application choisissent donc l'une des quatre variantes
 *    du groupe « Tratra Flash ». Les réglages du téléphone (silencieux, vibreur, Ne pas déranger) restent toujours respectés.
 *
 * Aucune permission réservée aux appels (ni écran plein, ni catégorie « appel ») : une alerte flottante avec actions, une version publique
 * neutre sur l'écran verrouillé, retirée automatiquement à l'échéance de la proposition.
 */
object TratraAlerts {
    const val CHANNEL_ACTIVITY = "tratra_activity"
    const val CHANNEL_FLASH = "tratra_new_missions"
    const val CHANNEL_FLASH_VIBRATE = "tratra_new_missions_vibrate"
    const val CHANNEL_FLASH_SOUND = "tratra_new_missions_sound"
    const val CHANNEL_FLASH_SILENT = "tratra_new_missions_silent"
    private const val GROUP_FLASH = "tratra_flash"
    private const val LEGACY_CHANNEL = "tratra_default"
    private const val PREFS = "tratra_flash"
    const val EXTRA_ACTION = "tratra_flash_action"
    const val EXTRA_OFFER = "tratra_flash_offer"
    private const val TAG = "tratra_flash"
    const val CHANNEL_ANNOUNCEMENTS = "tratra_announcements"
    const val EXTRA_LINK = "tratra_link"
    const val EXTRA_ANNOUNCEMENT = "tratra_announcement"
    const val EXTRA_NOTIFICATION = "tratra_notification"
    const val TAG_ANNOUNCEMENT = "tratra_announcement"
    /** Image d'une annonce : 1,5 Mo au plus (le serveur envoie un JPEG 2:1 d'environ 100 Ko), délais courts (réception en arrière-plan). */
    private const val IMAGE_MAX_BYTES = 1_500_000
    private val LINK = Regex("^tratra://[a-z_]+(/[0-9]+)?$")

    /** Vibration calée sur la sonnerie « Pulse » : six notes piquées (accents sur la 3e et la 6e), relancées, puis le double ping final. */
    val VIBRATION = longArrayOf(120, 50, 50, 50, 50, 80, 20, 50, 50, 50, 50, 80, 300, 50, 50, 50, 50, 80, 20, 50, 50, 50, 50, 80, 370, 120, 40, 350)

    /** Vrai quand une activité de l'application est au premier plan : l'alerte est alors affichée par l'écran Tratra Flash. */
    @Volatile var appVisible = false

    private var player: MediaPlayer? = null

    private val soundAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** Adresse par NOM de ressource (stable d'une version à l'autre, contrairement à l'identifiant numérique). */
    fun soundUri(context: Context, name: String): Uri {
        val raw = if (name == "tratra_notification") "tratra_notification" else "tratra_flash"
        return Uri.parse("android.resource://${context.packageName}/raw/$raw")
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannelGroup(NotificationChannelGroup(GROUP_FLASH, "Tratra Flash — nouvelles missions"))
        val green = Color.parseColor("#2E8B57")
        fun flash(id: String, name: String, sound: Boolean, vibrate: Boolean) =
            NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Propositions de missions à accepter ou refuser dans le délai indiqué."
                group = GROUP_FLASH
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                if (sound) setSound(soundUri(context, "tratra_flash"), soundAttributes) else setSound(null, null)
                enableVibration(vibrate)
                if (vibrate) vibrationPattern = VIBRATION
                enableLights(true)
                lightColor = green
                setShowBadge(true)
            }
        manager.createNotificationChannels(listOf(
            NotificationChannel(CHANNEL_ACTIVITY, "Réservations, messages et suivi", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Statut des réservations, arrivée du professionnel, messages et paiements."
                setSound(soundUri(context, "tratra_notification"), soundAttributes)
            },
            NotificationChannel("tratra_updates", "Avis et informations", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Nouveaux avis, activité de votre entreprise et informations de service."
            },
            NotificationChannel("tratra_announcements", "Annonces", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Annonces et nouveautés de Tratra."
            },
            flash(CHANNEL_FLASH, "Nouvelles missions", sound = true, vibrate = true),
            flash(CHANNEL_FLASH_VIBRATE, "Nouvelles missions (vibreur seul)", sound = false, vibrate = true),
            flash(CHANNEL_FLASH_SOUND, "Nouvelles missions (son seul)", sound = true, vibrate = false),
            flash(CHANNEL_FLASH_SILENT, "Nouvelles missions (sans son ni vibration)", sound = false, vibrate = false),
        ))
        // Ancien canal (son du système) remplacé par « tratra_activity » (son de la marque) : les notifications qui le citent encore
        // retombent sur le canal par défaut déclaré dans le manifeste (tratra_activity).
        manager.deleteNotificationChannel(LEGACY_CHANNEL)
    }

    // ── Réglages de l'application (son / vibration des nouvelles missions) ──────────────────────────────────────────────────────

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun soundEnabled(context: Context) = prefs(context).getBoolean("sound", true)

    fun vibrationEnabled(context: Context) = prefs(context).getBoolean("vibration", true)

    fun setPrefs(context: Context, sound: Boolean, vibration: Boolean) {
        prefs(context).edit().putBoolean("sound", sound).putBoolean("vibration", vibration).apply()
    }

    private fun flashChannel(context: Context): String {
        val s = soundEnabled(context)
        val v = vibrationEnabled(context)
        return when {
            s && v -> CHANNEL_FLASH
            s -> CHANNEL_FLASH_SOUND
            v -> CHANNEL_FLASH_VIBRATE
            else -> CHANNEL_FLASH_SILENT
        }
    }

    // ── Alerte système (application en arrière-plan ou fermée) ────────────────────────────────────────────────────────────────────

    /** `data` = charge utile du push (métier, zone, date, montant, délai). `sentAt` = heure d'envoi FCM (ms). */
    fun showOffer(context: Context, data: Map<String, String>, sentAt: Long) {
        val offer = data["id"]?.toIntOrNull() ?: return
        val ttl = data["expires_in"]?.toLongOrNull() ?: return
        val base = if (sentAt > 0) sentAt else System.currentTimeMillis()
        val deadline = base + ttl * 1000
        val remaining = deadline - System.currentTimeMillis()
        if (remaining < 3000) return                      // proposition déjà échue : aucune alerte
        ensureChannels(context)
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        val quote = data["mode"] == "quote"
        val title = data["title"] ?: "Nouvelle mission"
        // Le délai restant est affiché par le compte à rebours de la notification (jamais un nombre de secondes figé dans le texte).
        val parts = listOfNotNull(data["zone"], data["when_label"], data["amount_label"]).filter { it.isNotBlank() }
        val body = if (parts.isNotEmpty()) parts.joinToString(" · ") else (data["body"] ?: "")
        val green = ContextCompat.getColor(context, R.color.tratra_green)
        // Écran verrouillé sécurisé : seule cette version neutre est visible ; le détail et les actions exigent le déverrouillage.
        val public = NotificationCompat.Builder(context, flashChannel(context))
            .setSmallIcon(R.drawable.ic_stat_tratra)
            .setColor(green)
            .setContentTitle("Nouvelle mission Tratra")
            .setContentText("Déverrouillez pour voir et répondre.")
            .build()
        val builder = NotificationCompat.Builder(context, flashChannel(context))
            .setSmallIcon(R.drawable.ic_stat_tratra)
            .setColor(green)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setTimeoutAfter(remaining)                   // retirée d'elle-même à l'échéance
            .setWhen(deadline)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)                // compte à rebours du délai de réponse
            .setContentIntent(actionIntent(context, offer, "view", 0))
        if (quote) {
            builder.addAction(0, "Proposer un devis", actionIntent(context, offer, "view", 1))
        } else {
            builder.addAction(0, "Accepter", actionIntent(context, offer, "accept", 1))
        }
        builder.addAction(0, "Refuser", actionIntent(context, offer, "decline", 2))
        builder.addAction(0, "Voir", actionIntent(context, offer, "view", 3))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {     // avant Android 8, le son et la vibration sont portés par la notification
            if (soundEnabled(context)) builder.setSound(soundUri(context, "tratra_flash"))
            if (vibrationEnabled(context)) builder.setVibrate(VIBRATION)
        }
        try {
            nm.notify(TAG, offer, builder.build())
        } catch (_: SecurityException) {
            // autorisation des notifications retirée entre-temps
        }
    }

    private fun actionIntent(context: Context, offer: Int, action: String, slot: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = "com.tratra.FLASH.$action.$offer"
            putExtra(EXTRA_ACTION, action)
            putExtra(EXTRA_OFFER, offer)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(context, offer * 4 + slot, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun cancel(context: Context, offer: Int) {
        NotificationManagerCompat.from(context).cancel(TAG, offer)
    }

    // ── Annonces (application en arrière-plan ou fermée) ──────────────────────────────────────────────────────────────────────

    /**
     * Annonce reçue en message de DONNÉES (appareils « rich1 ») : grande image téléchargée (format 2:1, repli en texte seul si elle
     * est absente ou indisponible), logo Tratra en grande icône, bouton d'action, lien vers l'écran de l'application. Une même annonce
     * remplace sa notification précédente (jamais de doublon). Appelée hors du fil principal (téléchargement).
     */
    fun showAnnouncement(context: Context, data: Map<String, String>) {
        val id = data["id"]?.toIntOrNull() ?: return
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        ensureChannels(context)
        val title = data["title"]?.takeIf { it.isNotBlank() } ?: "Tratra"
        val body = data["body"].orEmpty()
        val link = data["deeplink"]?.takeIf { LINK.matches(it) } ?: "tratra://announcement/$id"
        val nid = data["nid"]?.toIntOrNull() ?: 0
        val picture = data["image"]?.let { downloadImage(context, it) }
        val builder = NotificationCompat.Builder(context, CHANNEL_ANNOUNCEMENTS)
            .setSmallIcon(R.drawable.ic_stat_tratra)
            .setColor(ContextCompat.getColor(context, R.color.tratra_green))
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.tratra_notification_large))
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(linkIntent(context, link, id, nid, 0))
        if (picture != null) {
            // Déroulée : l'image remplace le logo ; repliée : logo + texte.
            builder.setStyle(NotificationCompat.BigPictureStyle().bigPicture(picture).bigLargeIcon(null as Bitmap?).setSummaryText(body))
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }
        data["cta"]?.takeIf { it.isNotBlank() }?.let { builder.addAction(0, it.take(40), linkIntent(context, link, id, nid, 1)) }
        try {
            nm.notify(TAG_ANNOUNCEMENT, id, builder.build())
        } catch (_: SecurityException) {
            // autorisation des notifications retirée entre-temps
        }
    }

    private fun linkIntent(context: Context, link: String, announcement: Int, nid: Int, slot: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = "com.tratra.LINK.$announcement.$slot"
            putExtra(EXTRA_LINK, link)
            putExtra(EXTRA_ANNOUNCEMENT, announcement)
            putExtra(EXTRA_NOTIFICATION, nid)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(context, 100_000 + announcement * 2 + slot, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun cancelAnnouncement(context: Context, announcement: Int) {
        NotificationManagerCompat.from(context).cancel(TAG_ANNOUNCEMENT, announcement)
    }

    /** HTTPS uniquement (HTTP toléré dans une version de développement), sans redirection, type image, taille bornée, décodage réduit. */
    private fun downloadImage(context: Context, raw: String): Bitmap? {
        val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val scheme = Uri.parse(raw).scheme
        if (scheme != "https" && !(scheme == "http" && debuggable)) return null
        return try {
            val conn = URL(raw).openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 4000
                conn.readTimeout = 5000
                conn.instanceFollowRedirects = false
                conn.setRequestProperty("Accept", "image/*")
                if (conn.responseCode != HttpURLConnection.HTTP_OK) return null
                if (conn.contentType?.startsWith("image/") != true) return null
                val bytes = readCapped(conn.inputStream, IMAGE_MAX_BYTES) ?: return null
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= 1024) sample *= 2
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            } finally {
                conn.disconnect()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readCapped(input: InputStream, max: Int): ByteArray? = input.use {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            val n = it.read(buffer)
            if (n < 0) break
            if (out.size() + n > max) return null
            out.write(buffer, 0, n)
        }
        out.toByteArray()
    }

    // ── Lecture dans l'application (écran Tratra Flash, aperçu dans les réglages) ─────────────────────────────────────────────

    /** Joue le son (et/ou la vibration) en respectant le mode du téléphone : silencieux → rien, vibreur → vibration seule,
     *  « Ne pas déranger » → rien. Renvoie ce qui a réellement été joué. */
    fun play(context: Context, sound: String, withSound: Boolean, withVibration: Boolean): Map<String, Any> {
        stop(context)
        val audio = context.getSystemService(AudioManager::class.java)
        val nm = context.getSystemService(NotificationManager::class.java)
        val dnd = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && nm != null &&
            nm.currentInterruptionFilter > NotificationManager.INTERRUPTION_FILTER_ALL
        val ringer = when (audio?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "silent"
            AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
            else -> "normal"
        }
        var played = false
        var vibrated = false
        if (withSound && ringer == "normal" && !dnd) {
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(soundAttributes)
                    setDataSource(context, soundUri(context, sound))
                    setOnCompletionListener { it.release(); if (player === it) player = null }
                    prepare()
                    start()
                }
                played = true
            } catch (_: Exception) {
                player = null
            }
        }
        if (withVibration && ringer != "silent" && !dnd) {
            val pattern = if (sound == "tratra_notification") longArrayOf(0, 70, 50, 70, 50, 200) else VIBRATION
            vibrated = vibrate(context, pattern)
        }
        return mapOf("played" to played, "vibrated" to vibrated, "ringer" to ringer, "dnd" to dnd)
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun vibrate(context: Context, pattern: LongArray): Boolean {
        val v = vibrator(context) ?: return false
        if (!v.hasVibrator()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(pattern, -1)
        }
        return true
    }

    fun stop(context: Context) {
        try {
            player?.let { if (it.isPlaying) it.stop(); it.release() }
        } catch (_: Exception) {
        }
        player = null
        vibrator(context)?.cancel()
    }
}
