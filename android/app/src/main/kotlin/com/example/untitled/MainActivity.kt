package com.example.untitled

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import com.polar.androidcommunications.api.ble.model.DisInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApiCallback
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.model.PolarDeviceInfo
import com.polar.sdk.api.model.PolarHealthThermometerData
import com.polar.sdk.api.model.PolarHrData
import java.util.UUID

import io.reactivex.rxjava3.android.schedulers.AndroidSchedulers
import io.reactivex.rxjava3.disposables.CompositeDisposable
import io.reactivex.rxjava3.disposables.Disposable
import io.reactivex.rxjava3.schedulers.Schedulers


class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "PolarH10Demo"
        private const val METHOD_CHANNEL = "polar_h10_sdk/methods"
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var api: PolarBleApi
    private val disposables = CompositeDisposable()
    private var connectedDeviceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestBlePermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Polar API with only HR feature enabled
        api = PolarBleApiDefaultImpl.defaultImplementation(
            applicationContext,
            setOf(PolarBleApi.PolarBleSdkFeature.FEATURE_HR)
        )

        api.setApiCallback(object : PolarBleApiCallback() {

            override fun blePowerStateChanged(powered: Boolean) {
                Log.d(TAG, "BLE power: $powered")
            }

            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "CONNECTED: ${polarDeviceInfo.deviceId}")
                connectedDeviceId = polarDeviceInfo.deviceId
            }

            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "CONNECTING: ${polarDeviceInfo.deviceId}")
            }

            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                Log.d(TAG, "DISCONNECTED: ${polarDeviceInfo.deviceId}")
                if (connectedDeviceId == polarDeviceInfo.deviceId) {
                    connectedDeviceId = null
                }
            }

            override fun disInformationReceived(
                identifier: String,
                disInfo: DisInfo
            ) {
                Log.d(TAG, "DIS info from $identifier: $disInfo")
            }

            override fun bleSdkFeatureReady(identifier: String, feature: PolarBleApi.PolarBleSdkFeature) {
                Log.d(TAG, "Polar BLE SDK feature $feature is ready for $identifier")
            }

/*
            override fun disInformationReceived(identifier: String, uuid: UUID, value: String) {
                Log.d(TAG, "DIS info from $identifier: uuid=$uuid value=$value")
            }
*/

            override fun htsNotificationReceived(
                identifier: String,
                data: PolarHealthThermometerData
            ) {
                Log.d(TAG, "HTS notification from $identifier: $data")
            }

            override fun batteryLevelReceived(identifier: String, level: Int) {
                Log.d(TAG, "Battery level from $identifier: $level")
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "searchAndConnect" -> searchAndConnect(result)
                "getOneHrSample"    -> getOneHrSample(result)
                else                -> result.notImplemented()
            }
        }
    }

    private fun requestBlePermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        } else {
            permissions += Manifest.permission.ACCESS_COARSE_LOCATION
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissions.toTypedArray(),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    private fun searchAndConnect(result: MethodChannel.Result) {
        Log.d(TAG, "Starting searchForDevice()")
        val disposable = api.searchForDevice()
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ deviceInfo ->
                Log.d(TAG, "Found device: ${deviceInfo.deviceId} ${deviceInfo.name}")

                // You can filter to H10 specifically, e.g. by name or type
                // For demo, just take the first Polar device and stop scanning.
                disposables.clear()

                try {
                    api.connectToDevice(deviceInfo.deviceId)
                    result.success(deviceInfo.deviceId)
                } catch (e: Exception) {
                    Log.e(TAG, "Error connecting: ${e.message}", e)
                    result.error("CONNECT_ERROR", e.message, null)
                }
            }, { error ->
                Log.e(TAG, "searchForDevice error: ${error.message}", error)
                result.error("SEARCH_ERROR", error.message, null)
            })

        disposables.add(disposable)
    }

    private fun getOneHrSample(result: MethodChannel.Result) {
        val id = connectedDeviceId
        if (id == null) {
            result.error("NO_DEVICE", "No device connected", null)
            return
        }

        Log.d(TAG, "Starting HR streaming for $id")

        var disposable: Disposable? = null
        disposable = api.startHrStreaming(id)
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe({ hrData ->
                // PolarHrData typically contains a list of samples
                val sample = hrData.samples.firstOrNull()
                val hr = sample?.hr?.toInt() ?: -1
                Log.d(TAG, "Received HR sample: $hr")
                result.success(hr)

                // After we got one sample, stop streaming for this simple demo
                disposable?.dispose()
            }, { error ->
                Log.e(TAG, "HR streaming error: ${error.message}", error)
                result.error("HR_ERROR", error.message, null)
            })

        if (disposable != null) {
            disposables.add(disposable)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        disposables.clear()
        api.shutDown()
    }
}