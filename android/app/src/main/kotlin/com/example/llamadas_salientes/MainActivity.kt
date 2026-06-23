package com.example.llamadas_salientes

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CallLog
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val channelName = "registro_llamadas/call_log"
    private val permissionRequestCode = 7001
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCallPermissions" -> {
                    requestCallPermissions(result)
                }

                "getOutgoingCalls" -> {
                    if (!hasRequiredPermissions()) {
                        result.error(
                            "PERMISSION_DENIED",
                            "No se concedieron los permisos necesarios.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    val from = getLongArgument(call, "from", 0L)
                    val to = getLongArgument(call, "to", System.currentTimeMillis())

                    try {
                        val calls = getOutgoingCalls(from, to)
                        result.success(calls)
                    } catch (error: Exception) {
                        result.error(
                            "CALL_LOG_ERROR",
                            error.message ?: "Error leyendo el registro de llamadas.",
                            null
                        )
                    }
                }

                "scheduleDailyCallSync" -> {
                    if (!hasRequiredPermissions()) {
                        result.error(
                            "PERMISSION_DENIED",
                            "No se concedieron los permisos necesarios.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    scheduleDailyCallSync()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        if (hasRequiredPermissions()) {
            scheduleDailyCallSync()
        }
    }

    private fun requestCallPermissions(result: MethodChannel.Result) {
        if (hasRequiredPermissions()) {
            scheduleDailyCallSync()
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            scheduleDailyCallSync()
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_ACTIVE",
                "Ya existe una solicitud de permisos en curso.",
                null
            )
            return
        }

        pendingPermissionResult = result

        requestPermissions(
            arrayOf(
                Manifest.permission.READ_CALL_LOG,
                Manifest.permission.READ_CONTACTS
            ),
            permissionRequestCode
        )
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        val callLogGranted = checkSelfPermission(
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        val contactsGranted = checkSelfPermission(
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        return callLogGranted && contactsGranted
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != permissionRequestCode) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        if (granted) {
            scheduleDailyCallSync()
        }

        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun getOutgoingCalls(
        fromTimestamp: Long,
        toTimestamp: Long
    ): List<Map<String, Any?>> {
        val calls = mutableListOf<Map<String, Any?>>()

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

        val cursor = contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )

        cursor?.use {
            val androidIdIndex = it.getColumnIndexOrThrow(CallLog.Calls._ID)
            val numberIndex = it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val nameIndex = it.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
            val dateIndex = it.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durationIndex = it.getColumnIndexOrThrow(CallLog.Calls.DURATION)

            val dateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val timeFormatter = SimpleDateFormat("HH:mm", Locale.US)

            while (it.moveToNext()) {
                val androidId = it.getLong(androidIdIndex)
                val number = it.getString(numberIndex) ?: ""
                val cachedName = it.getString(nameIndex) ?: ""
                val timestamp = it.getLong(dateIndex)
                val duration = it.getInt(durationIndex)
                val date = Date(timestamp)

                calls.add(
                    mapOf(
                        "android_id" to androidId,
                        "numero" to number,
                        "nombre_contacto" to cachedName,
                        "fecha" to dateFormatter.format(date),
                        "hora" to timeFormatter.format(date),
                        "duracion" to duration,
                        "estado" to mapOutgoingStatus(duration),
                        "timestamp" to timestamp
                    )
                )
            }
        }

        return calls
    }

    private fun mapOutgoingStatus(duration: Int): String {
        return if (duration > 0) {
            "Respondida"
        } else {
            "No respondida"
        }
    }

    private fun getLongArgument(
        call: MethodCall,
        key: String,
        defaultValue: Long
    ): Long {
        val value = call.argument<Any>(key) ?: return defaultValue

        return when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Double -> value.toLong()
            is Float -> value.toLong()
            else -> defaultValue
        }
    }

    private fun scheduleDailyCallSync() {
        val initialDelay = calculateInitialDelayMillis(
            targetHour = 23,
            targetMinute = 59
        )

        val request = PeriodicWorkRequestBuilder<OutgoingCallSyncWorker>(
            1,
            TimeUnit.DAYS
        )
            .setInitialDelay(initialDelay, TimeUnit.MILLISECONDS)
            .addTag(OutgoingCallSyncWorker.WORK_NAME)
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            OutgoingCallSyncWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }

    private fun calculateInitialDelayMillis(
        targetHour: Int,
        targetMinute: Int
    ): Long {
        val now = Calendar.getInstance()

        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, targetHour)
            set(Calendar.MINUTE, targetMinute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)

            if (timeInMillis <= now.timeInMillis) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        return target.timeInMillis - now.timeInMillis
    }
}