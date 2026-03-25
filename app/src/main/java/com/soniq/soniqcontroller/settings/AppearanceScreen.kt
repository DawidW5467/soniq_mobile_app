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
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.soniq.soniqcontroller.ui.settings.FontScale
import androidx.compose.material3.FilterChip
import androidx.compose.ui.res.stringResource
import com.soniq.soniqcontroller.R

@Composable
fun AppearanceScreen(
    highContrast: Boolean,
    onHighContrastChange: (Boolean) -> Unit,
    replaceIconsWithText: Boolean,
    onReplaceIconsChange: (Boolean) -> Unit,
    fontScale: FontScale,
    onFontScaleChange: (FontScale) -> Unit,
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
            text = stringResource(R.string.accessibility_title),
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(Modifier.height(24.dp))

        SettingsOption(stringResource(R.string.high_contrast_title),stringResource(R.string.high_contrast_subtitle),highContrast,onHighContrastChange)

        SettingsOption(
            title = stringResource(R.string.replacing_icons_title),
            subtitle = stringResource(R.string.replacing_icons_subtitle),
            checked = replaceIconsWithText,
            onCheckedChange = onReplaceIconsChange
        )

        Spacer(Modifier.height(24.dp))

        FontSizeOption(
            selected = fontScale,
            onSelected = onFontScaleChange
        )

    }
}


@Composable
fun SettingsOption(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
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

        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )


    }
}


@Composable
fun FontSizeOption(
    selected: FontScale,
    onSelected: (FontScale) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {

        Text(stringResource(R.string.font_size_title))
        Spacer(Modifier.height(8.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FontScale.entries.forEach { scale ->
                FilterChip(
                    selected = scale == selected,
                    onClick = { onSelected(scale) },
                    label = { Text(text = stringResource(id = scale.labelRes))}
                )
            }
        }
    }
}



@Preview(showBackground = true)
@Composable
fun ApperanceScreenPrewiev(){
    MaterialTheme() {
        AppearanceScreen(false,{},false,{}, FontScale.SMALL,{},{})
    }
}