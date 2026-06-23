package com.example.llamadas_salientes

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.provider.CallLog
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class OutgoingCallSyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    companion object {
        const val WORK_NAME = "outgoing_call_daily_sync"

        // Cambia este nombre por el nombre real usado en lib/core/database/app_database.dart
        private const val DATABASE_NAME = "registro_llamadas_salientes.db"
    }

    override fun doWork(): Result {
        if (!hasRequiredPermissions()) {
            return Result.success()
        }

        return try {
            val db = openDatabase()
            ensureSchema(db)

            val now = System.currentTimeMillis()

            // Lee las últimas 48 horas para evitar perder llamadas si Android retrasa el Worker.
            // Los duplicados se evitan con timestamp + numero.
            val from = now - 48L * 60L * 60L * 1000L
            val to = now

            val excludedRules = getExcludedRules(db)
            val inserted = syncOutgoingCalls(db, excludedRules, from, to)

            db.close()

            Result.success()
        } catch (error: Exception) {
            Result.retry()
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        val callLogGranted = ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        val contactsGranted = ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        return callLogGranted && contactsGranted
    }

    private fun openDatabase(): SQLiteDatabase {
        val dbFile = applicationContext.getDatabasePath(DATABASE_NAME)
        dbFile.parentFile?.mkdirs()
        return SQLiteDatabase.openOrCreateDatabase(dbFile, null)
    }

    private fun ensureSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS llamadas_salientes (
                id INTEGER PRIMARY KEY,
                fecha DATE,
                hora TIME,
                numero TEXT,
                nombre_contacto TEXT,
                duracion INTEGER,
                estado TEXT,
                timestamp INTEGER
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS numeros_excluidos (
                id INTEGER PRIMARY KEY,
                numero TEXT,
                tipo TEXT
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_llamadas_timestamp_numero
            ON llamadas_salientes(timestamp, numero)
            """.trimIndent()
        )
    }

    private fun getExcludedRules(db: SQLiteDatabase): List<ExcludedRule> {
        val rules = mutableListOf<ExcludedRule>()

        val cursor = db.query(
            "numeros_excluidos",
            arrayOf("numero", "tipo"),
            null,
            null,
            null,
            null,
            "id DESC"
        )

        cursor?.use {
            val numberIndex = it.getColumnIndexOrThrow("numero")
            val typeIndex = it.getColumnIndexOrThrow("tipo")

            while (it.moveToNext()) {
                val number = it.getString(numberIndex) ?: ""
                val type = it.getString(typeIndex) ?: ""

                if (number.isNotBlank() && type.isNotBlank()) {
                    rules.add(
                        ExcludedRule(
                            numero = number,
                            tipo = type
                        )
                    )
                }
            }
        }

        return rules
    }

    private fun syncOutgoingCalls(
        db: SQLiteDatabase,
        excludedRules: List<ExcludedRule>,
        fromTimestamp: Long,
        toTimestamp: Long
    ): Int {
        var inserted = 0

        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.TYPE
        )

        val selection = """
            ${CallLog.Calls.TYPE} = ?
            AND ${CallLog.Calls.DATE} >= ?
            AND ${CallLog.Calls.DATE} <= ?
        """.trimIndent()

        val selectionArgs = arrayOf(
            CallLog.Calls.OUTGOING_TYPE.toString(),
            fromTimestamp.toString(),
            toTimestamp.toString()
        )

        val sortOrder = "${CallLog.Calls.DATE} DESC"

        val cursor = applicationContext.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )

        cursor?.use {
            val numberIndex = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val nameIndex = it.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
            val dateIndex = it.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durationIndex = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)

            val dateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val timeFormatter = SimpleDateFormat("HH:mm", Locale.US)

            while (it.moveToNext()) {
                val number = normalizeSpaces(it.getString(numberIndex) ?: "")

                if (number.isBlank()) {
                    continue
                }

                if (isExcluded(number, excludedRules)) {
                    continue
                }

                val cachedName = normalizeSpaces(it.getString(nameIndex) ?: "")
                val timestamp = it.getLong(dateIndex)
                val duration = it.getInt(durationIndex)
                val date = Date(timestamp)

                val values = ContentValues().apply {
                    put("fecha", dateFormatter.format(date))
                    put("hora", timeFormatter.format(date))
                    put("numero", number)
                    put("nombre_contacto", cachedName)
                    put("duracion", duration)
                    put("estado", mapOutgoingStatus(duration))
                    put("timestamp", timestamp)
                }

                val result = db.insertWithOnConflict(
                    "llamadas_salientes",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_IGNORE
                )

                if (result > 0) {
                    inserted++
                }
            }
        }

        return inserted
    }

    private fun isExcluded(
        number: String,
        excludedRules: List<ExcludedRule>
    ): Boolean {
        val cleanNumber = normalizePhoneForComparison(number)

        if (cleanNumber.isBlank()) {
            return false
        }

        for (rule in excludedRules) {
            val cleanRuleNumber = normalizePhoneForComparison(rule.numero)

            if (cleanRuleNumber.isBlank()) {
                continue
            }

            when (rule.tipo.lowercase(Locale.US)) {
                "exacto" -> {
                    if (cleanNumber == cleanRuleNumber) {
                        return true
                    }
                }

                "prefijo" -> {
                    if (cleanNumber.startsWith(cleanRuleNumber)) {
                        return true
                    }
                }
            }
        }

        return false
    }

    private fun mapOutgoingStatus(duration: Int): String {
        return if (duration > 0) {
            "Respondida"
        } else {
            "No respondida"
        }
    }

    private fun normalizeSpaces(value: String): String {
        return value.replace(Regex("\\s+"), " ").trim()
    }

    private fun normalizePhoneForComparison(value: String): String {
        var clean = normalizeSpaces(value)
            .replace(Regex("[\\s\\-()]+"), "")
            .trim()

        if (clean.startsWith("+57")) {
            clean = clean.removePrefix("+57")
        } else if (clean.startsWith("57") && clean.length > 10) {
            clean = clean.removePrefix("57")
        }

        return clean
    }

    data class ExcludedRule(
        val numero: String,
        val tipo: String
    )
}