package com.makako.makako

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the sticker packs created in Flutter to WhatsApp.
 *
 * Flutter writes `filesDir/stickers/contents.json` plus one folder per pack
 * (`filesDir/stickers/<identifier>/`) holding the tray PNG and the WebP stickers.
 * The contract (URIs + column names) follows WhatsApp's official sample app.
 */
class StickerContentProvider : ContentProvider() {

    companion object {
        const val METADATA = "metadata"
        const val STICKERS = "stickers"
        const val STICKERS_ASSET = "stickers_asset"

        private const val METADATA_ALL = 1
        private const val METADATA_SINGLE = 2
        private const val STICKERS_CODE = 3
        private const val STICKER_FILE = 4
        private const val TRAY_FILE = 5

        // Pack columns
        const val PACK_ID = "sticker_pack_identifier"
        const val PACK_NAME = "sticker_pack_name"
        const val PACK_PUBLISHER = "sticker_pack_publisher"
        const val PACK_ICON = "sticker_pack_icon"
        const val ANDROID_LINK = "android_play_store_link"
        const val IOS_LINK = "ios_app_download_link"
        const val PUBLISHER_EMAIL = "sticker_pack_publisher_email"
        const val PUBLISHER_WEBSITE = "sticker_pack_publisher_website"
        const val PRIVACY_POLICY = "sticker_pack_privacy_policy_website"
        const val LICENSE = "sticker_pack_license_agreement_website"
        const val IMAGE_DATA_VERSION = "image_data_version"
        const val AVOID_CACHE = "whatsapp_will_not_cache_stickers"
        const val ANIMATED = "animated_sticker_pack"

        // Sticker columns
        const val STICKER_FILE_NAME = "sticker_file_name"
        const val STICKER_EMOJI = "sticker_emoji"
        const val STICKER_A11Y = "sticker_accessibility_text"
    }

    private val matcher = UriMatcher(UriMatcher.NO_MATCH)
    private lateinit var authority: String

    override fun onCreate(): Boolean {
        authority = "${context!!.packageName}.stickercontentprovider"
        matcher.addURI(authority, METADATA, METADATA_ALL)
        matcher.addURI(authority, "$METADATA/*", METADATA_SINGLE)
        matcher.addURI(authority, "$STICKERS/*", STICKERS_CODE)
        matcher.addURI(authority, "$STICKERS_ASSET/*/*", STICKER_FILE)
        matcher.addURI(authority, "$STICKERS_ASSET/*/*/*", TRAY_FILE)
        return true
    }

    private fun root(): File = File(context!!.filesDir, "stickers")

    private fun readPacks(): List<JSONObject> {
        val f = File(root(), "contents.json")
        if (!f.exists()) return emptyList()
        return try {
            val arr = JSONObject(f.readText()).optJSONArray("sticker_packs") ?: return emptyList()
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?
    ): Cursor {
        return when (matcher.match(uri)) {
            METADATA_ALL -> packsCursor(uri, readPacks())
            METADATA_SINGLE -> packsCursor(uri, readPacks().filter { it.getString("identifier") == uri.lastPathSegment })
            STICKERS_CODE -> stickersCursor(uri, uri.lastPathSegment ?: "")
            else -> throw IllegalArgumentException("Unknown URI: $uri")
        }
    }

    private fun packsCursor(uri: Uri, packs: List<JSONObject>): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                PACK_ID, PACK_NAME, PACK_PUBLISHER, PACK_ICON, ANDROID_LINK, IOS_LINK,
                PUBLISHER_EMAIL, PUBLISHER_WEBSITE, PRIVACY_POLICY, LICENSE,
                IMAGE_DATA_VERSION, AVOID_CACHE, ANIMATED
            )
        )
        for (p in packs) {
            cursor.addRow(
                arrayOf<Any>(
                    p.getString("identifier"),
                    p.getString("name"),
                    p.optString("publisher", "Makako"),
                    p.getString("tray_image_file"),
                    "", "", "", "", "", "",
                    p.optString("image_data_version", "1"),
                    if (p.optBoolean("avoid_cache", false)) 1 else 0,
                    if (p.optBoolean("animated_sticker_pack", false)) 1 else 0,
                )
            )
        }
        cursor.setNotificationUri(context!!.contentResolver, uri)
        return cursor
    }

    private fun stickersCursor(uri: Uri, identifier: String): Cursor {
        val cursor = MatrixCursor(arrayOf(STICKER_FILE_NAME, STICKER_EMOJI, STICKER_A11Y))
        val pack = readPacks().firstOrNull { it.getString("identifier") == identifier }
        val stickers = pack?.optJSONArray("stickers")
        if (stickers != null) {
            for (i in 0 until stickers.length()) {
                val s = stickers.getJSONObject(i)
                val emojis = s.optJSONArray("emojis")
                val emojiStr = if (emojis == null) "" else
                    (0 until emojis.length()).joinToString(",") { emojis.getString(it) }
                cursor.addRow(arrayOf<Any>(s.getString("image_file"), emojiStr, s.optString("accessibility_text", "")))
            }
        }
        cursor.setNotificationUri(context!!.contentResolver, uri)
        return cursor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        val segments = uri.pathSegments
        if (segments.size != 3 || segments[0] != STICKERS_ASSET) {
            throw FileNotFoundException("Unsupported uri: $uri")
        }
        val identifier = segments[1]
        val fileName = segments[2]
        // Prevent path traversal: only plain file names inside the pack folder.
        if (identifier.contains("/") || identifier.contains("..") || fileName.contains("/") || fileName.contains("..")) {
            throw FileNotFoundException("Invalid path")
        }
        val file = File(File(root(), identifier), fileName)
        if (!file.exists()) throw FileNotFoundException("Not found: $fileName")
        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    override fun getType(uri: Uri): String? = when (matcher.match(uri)) {
        METADATA_ALL -> "vnd.android.cursor.dir/vnd.$authority.$METADATA"
        METADATA_SINGLE -> "vnd.android.cursor.item/vnd.$authority.$METADATA"
        STICKERS_CODE -> "vnd.android.cursor.dir/vnd.$authority.$STICKERS"
        STICKER_FILE -> if (uri.lastPathSegment?.endsWith(".png") == true) "image/png" else "image/webp"
        else -> null
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
}
