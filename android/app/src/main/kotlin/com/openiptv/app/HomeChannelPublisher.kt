package com.openiptv.app

import android.annotation.TargetApi
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.media.tv.TvContract
import android.net.Uri
import android.os.Build
import java.io.IOException

/** Keeps this app's live preview cards in sync without changing the user's channel visibility. */
class HomeChannelPublisher(private val context: Context) {
    private val resolver = context.contentResolver

    fun sync(cards: List<Map<String, String>>): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !EngineChannels.isTelevision(context)) {
            return mapOf("status" to "unsupported", "reason" to "requires_tv_api26")
        }
        val desired = validate(cards)
            ?: return mapOf("status" to "failed", "reason" to "invalid_cards")
        return try {
            publish(desired)
        } catch (_: SecurityException) {
            mapOf("status" to "failed", "reason" to "permission_denied")
        } catch (_: Exception) {
            // Provider exceptions can include source metadata. Keep them out of platform results.
            mapOf("status" to "failed", "reason" to "provider_error")
        }
    }

    private fun validate(cards: List<Map<String, String>>): List<Map<String, String>>? {
        if (cards.size > 12) return null
        val ids = mutableSetOf<String>()
        for (card in cards) {
            val fields: Map<*, *> = card
            val id = fields["id"] as? String ?: return null
            val title = fields["title"] as? String ?: return null
            if (fields["artUri"] != null && fields["artUri"] !is String) return null
            if (id.isBlank() || id.length > 256 || id.any { it < ' ' } || title.isBlank() || title.length > 512 ||
                !ids.add(id) || !validLink(fields["intentUri"] as? String, id)
            ) return null
        }
        return cards
    }

    private fun validLink(value: String?, id: String): Boolean {
        if (value == null) return false
        val uri = Uri.parse(value)
        return uri.scheme == "fireiptv" && uri.encodedAuthority == "channel" &&
            uri.query == null && uri.fragment == null && uri.pathSegments.size == 1 &&
            uri.pathSegments.single() == id
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun publish(cards: List<Map<String, String>>): Map<String, Any?> {
        var channelId = findChannel()
        if (channelId == null && cards.isEmpty()) {
            return mapOf("status" to "empty", "published" to 0, "removed" to 0)
        }
        val created = channelId == null
        val values = ContentValues().apply {
            put(TvContract.Channels.COLUMN_TYPE, TvContract.Channels.TYPE_PREVIEW)
            put(TvContract.Channels.COLUMN_DISPLAY_NAME, "Fire IPTV")
            put(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID, CHANNEL_KEY)
            if (cards.isNotEmpty()) {
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: throw IllegalStateException("Launcher unavailable")
                put(TvContract.Channels.COLUMN_APP_LINK_INTENT_URI, launch.toUri(0))
            }
        }
        if (channelId == null) {
            val uri = resolver.insert(TvContract.Channels.CONTENT_URI, values)
                ?: throw IOException("Channel insert failed")
            channelId = ContentUris.parseId(uri)
        } else if (cards.isNotEmpty()) {
            if (resolver.update(TvContract.buildChannelUri(channelId), values, null, null) != 1) {
                throw IOException("Channel update failed")
            }
        }
        if (cards.isNotEmpty()) storeLogo(channelId)
        val existing = readPrograms(channelId)
        val operations = arrayListOf<ContentProviderOperation>()
        var inserted = 0
        var updated = 0
        val retained = mutableSetOf<Long>()
        for ((index, card) in cards.withIndex()) {
            val row = existing.firstOrNull { it.second == card.getValue("id") && it.first !in retained }
            val program = programValues(channelId, card, cards.size - index)
            if (row == null) {
                operations += ContentProviderOperation.newInsert(TvContract.PreviewPrograms.CONTENT_URI)
                    .withValues(program).build()
                inserted++
            } else {
                retained += row.first
                operations += ContentProviderOperation.newUpdate(TvContract.buildPreviewProgramUri(row.first))
                    .withValues(program).withExpectedCount(1).build()
                updated++
            }
        }
        val stale = existing.filter { it.first !in retained }
        for ((id, _) in stale) {
            operations += ContentProviderOperation.newDelete(TvContract.buildPreviewProgramUri(id))
                .withExpectedCount(1).build()
        }
        if (operations.isNotEmpty()) resolver.applyBatch(TvContract.AUTHORITY, operations)
        // Never set COLUMN_BROWSABLE or re-request an existing channel the user may have hidden.
        if (created) TvContract.requestChannelBrowsable(context, channelId)
        return mapOf(
            "status" to if (cards.isEmpty()) "empty" else "published",
            "channelId" to channelId,
            "published" to cards.size,
            "inserted" to inserted,
            "updated" to updated,
            "removed" to stale.size,
        )
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun findChannel(): Long? {
        val projection = arrayOf(
            TvContract.Channels._ID,
            TvContract.Channels.COLUMN_PACKAGE_NAME,
            TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID,
            TvContract.Channels.COLUMN_TYPE,
        )
        val cursor = resolver.query(TvContract.Channels.CONTENT_URI, projection, null, null, null)
            ?: throw IOException("Channels unavailable")
        cursor.use {
            while (it.moveToNext()) {
                if (it.getString(1) == context.packageName && it.getString(2) == CHANNEL_KEY &&
                    it.getString(3) == TvContract.Channels.TYPE_PREVIEW
                ) return it.getLong(0)
            }
        }
        return null
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun readPrograms(channelId: Long): List<Pair<Long, String?>> {
        val rows = mutableListOf<Pair<Long, String?>>()
        val projection = arrayOf(
            TvContract.PreviewPrograms._ID,
            TvContract.PreviewPrograms.COLUMN_INTERNAL_PROVIDER_ID,
            TvContract.PreviewPrograms.COLUMN_PACKAGE_NAME,
            TvContract.PreviewPrograms.COLUMN_CHANNEL_ID,
        )
        val cursor = resolver.query(
            TvContract.buildPreviewProgramsUriForChannel(channelId), projection, null, null, null,
        ) ?: throw IOException("Programs unavailable")
        cursor.use {
            while (it.moveToNext()) {
                if (it.getString(2) == context.packageName && it.getLong(3) == channelId) {
                    rows += it.getLong(0) to it.getString(1)
                }
            }
        }
        return rows
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun programValues(channelId: Long, card: Map<String, String>, weight: Int): ContentValues =
        ContentValues().apply {
            put(TvContract.PreviewPrograms.COLUMN_CHANNEL_ID, channelId)
            put(TvContract.PreviewPrograms.COLUMN_INTERNAL_PROVIDER_ID, card.getValue("id"))
            put(TvContract.PreviewPrograms.COLUMN_TITLE, card.getValue("title"))
            put(TvContract.PreviewPrograms.COLUMN_TYPE, TvContract.PreviewPrograms.TYPE_CHANNEL)
            put(TvContract.PreviewPrograms.COLUMN_LIVE, 1)
            val launch = Intent(Intent.ACTION_VIEW, Uri.parse(card.getValue("intentUri")))
                .setPackage(context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            put(TvContract.PreviewPrograms.COLUMN_INTENT_URI, launch.toUri(Intent.URI_INTENT_SCHEME))
            put(TvContract.PreviewPrograms.COLUMN_POSTER_ART_URI, artwork(card["artUri"]))
            put(TvContract.PreviewPrograms.COLUMN_LOGO_URI, artwork(card["artUri"]))
            put(TvContract.PreviewPrograms.COLUMN_POSTER_ART_ASPECT_RATIO, TvContract.PreviewPrograms.ASPECT_RATIO_16_9)
            put(TvContract.PreviewPrograms.COLUMN_WEIGHT, weight)
        }

    private fun artwork(value: String?): String {
        val fallback = "android.resource://${context.packageName}/drawable/tv_banner"
        if (value.isNullOrBlank()) return fallback
        val uri = Uri.parse(value)
        return if ((uri.scheme == "https" || uri.scheme == "http") && !uri.host.isNullOrBlank() &&
            uri.userInfo == null && uri.query == null && uri.fragment == null
        ) value else fallback
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun storeLogo(channelId: Long) {
        val icon = context.packageManager.getApplicationIcon(context.packageName)
        val bitmap = Bitmap.createBitmap(160, 160, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.rgb(15, 23, 42))
            icon.setBounds(0, 0, bitmap.width, bitmap.height)
            icon.draw(canvas)
            val output = resolver.openOutputStream(TvContract.buildChannelLogoUri(channelId))
                ?: throw IOException("Channel logo unavailable")
            output.use {
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) {
                    throw IOException("Channel logo encoding failed")
                }
            }
        } finally {
            bitmap.recycle()
        }
    }

    private companion object {
        const val CHANNEL_KEY = "fire-iptv-live-v1"
    }
}
