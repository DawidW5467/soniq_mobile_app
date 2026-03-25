package com.soniq.soniqcontroller.settings


import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.soniq.soniqcontroller.R

@Composable
fun SystemInfoScreen(
    onBack: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {

        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }

        Text(
            text = "System",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(Modifier.height(24.dp))



        SettingsInfo(stringResource(R.string.system_info_device_name), "SONIQ Player")
        SettingsInfo(stringResource(R.string.system_info_model_name),"SONIQ S1000")
        SettingsInfo(stringResource(R.string.system_info_firmware_version),"v2.3.1 (2025-01-04)")
        SettingsInfo(stringResource(R.string.system_info_working_time),"3 d 14 h")

    }
}

@Composable
fun SettingsInfo(
    title: String,
    subtitle: String,
){
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(title)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}


@Preview(showBackground = true)
@Composable
fun SystemInfoScreenPreview(){
    MaterialTheme() {
        SystemInfoScreen ({})
    }
}