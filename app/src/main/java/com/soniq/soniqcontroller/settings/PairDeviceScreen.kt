package com.soniq.soniqcontroller.settings
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ListItem
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.ui.res.stringResource
import com.soniq.soniqcontroller.R
import androidx.compose.ui.platform.LocalContext
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.journeyapps.barcodescanner.ScanContract
import android.widget.Toast;
import com.journeyapps.barcodescanner.ScanOptions

@Composable
fun PairDeviceScreen(
    onBack: () -> Unit,
    onPaired: (String?, String?) -> Unit
) {
    val context = LocalContext.current

    var scannedToken by rememberSaveable { mutableStateOf("") }
    var pairingCode by rememberSaveable { mutableStateOf("") }

    val launcher = rememberLauncherForActivityResult(
        contract = ScanContract()
    ) { result ->
        result.contents?.let { token ->
            scannedToken = token

            Toast.makeText(
                context,
                "Zeskanowano token:\n$token",
                Toast.LENGTH_LONG
            ).show()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {

        Text(
            text = "Parowanie urządzenia",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = {
                launcher.launch(
                    ScanOptions().apply {
                        setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                        setPrompt("Zeskanuj kod QR")
                        setBeepEnabled(false)
                        setOrientationLocked(true)
                    }
                )
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Zeskanuj QR (token)")
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (scannedToken.isNotBlank()) {
            Text(
                text = "Token: $scannedToken",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(modifier = Modifier.height(16.dp))
        }

        OutlinedTextField(
            value = pairingCode,
            onValueChange = { pairingCode = it },
            label = { Text("Kod parowania (opcjonalnie)") },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = {

                if (scannedToken.isNotBlank() || pairingCode.isNotBlank()) {

                    Toast.makeText(
                        context,
                        "Łączenie...",
                        Toast.LENGTH_SHORT
                    ).show()

                    onPaired(
                        scannedToken.ifBlank { null },
                        pairingCode.ifBlank { null }
                    )

                } else {
                    Toast.makeText(
                        context,
                        "Podaj token lub kod parowania",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Połącz")
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Wróć")
        }
    }
}