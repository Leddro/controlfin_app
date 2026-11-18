package br.com.controlfin.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Fila das notificações dos bancos, guardada só no celular.
 *
 * O serviço de leitura grava aqui mesmo com o app fechado; o app lê pelo
 * canal "controlfin/bank_notifications" e marca o que foi confirmado,
 * descartado ou validado. O texto nunca sai do celular por este caminho.
 */
object NotificationStore {
    private const val PREFS = "controlfin_bank_notifications"
    private const val KEY = "items"

    /** Guarda no máximo este tanto; as mais antigas saem primeiro. */
    private const val MAX_ITEMS = 300

    /** Mesma notificação repetida dentro deste intervalo é ignorada. */
    private const val DUPLICATE_WINDOW_MS = 2 * 60 * 1000L

    private fun read(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            JSONArray()
        }
    }

    private fun write(context: Context, items: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, items.toString()).apply()
    }

    /** Devolve true se a notificação era nova. */
    @Synchronized
    fun add(
        context: Context,
        pkg: String,
        title: String,
        text: String,
        postTime: Long,
    ): Boolean {
        val items = read(context)
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            if (o.optString("package") == pkg &&
                o.optString("title") == title &&
                o.optString("text") == text &&
                Math.abs(o.optLong("postedAt") - postTime) < DUPLICATE_WINDOW_MS
            ) return false
        }
        items.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("package", pkg)
                .put("title", title)
                .put("text", text)
                .put("postedAt", postTime)
        )
        val start = maxOf(0, items.length() - MAX_ITEMS)
        val trimmed = JSONArray()
        for (i in start until items.length()) trimmed.put(items.get(i))
        write(context, trimmed)
        return true
    }

    @Synchronized
    fun list(context: Context): String = read(context).toString()

    /** Grava campos de uma notificação (status, feedback, note). Nulo apaga. */
    @Synchronized
    fun update(context: Context, id: String, fields: Map<String, Any?>) {
        val items = read(context)
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            if (o.optString("id") != id) continue
            for ((key, value) in fields) {
                if (value == null) o.remove(key) else o.put(key, value)
            }
        }
        write(context, items)
    }

    @Synchronized
    fun remove(context: Context, ids: Collection<String>) {
        val items = read(context)
        val kept = JSONArray()
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            if (o.optString("id") !in ids) kept.put(o)
        }
        write(context, kept)
    }
}
