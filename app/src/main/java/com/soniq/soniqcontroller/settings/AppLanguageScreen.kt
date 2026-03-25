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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue


data class AppLanguage(
    val code: String,
    val nativeName: String,
    val englishName: String
)



@Composable
fun AppLanguageScreen(
    selectedLanguageCode: String,
    onLanguageSelected: (String) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var currentLanguage by rememberSaveable {
        mutableStateOf(selectedLanguageCode)
    }

    val languages = listOf(
        AppLanguage("en", "English", "English"),
        AppLanguage("pl", "Polski", "Polish")

    )

    LazyColumn(
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            IconButton(
                onClick = onBack,
                modifier = Modifier.padding(8.dp)
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back"
                )
            }
        }

        item {
            Text(
                text = stringResource(R.string.language_title),
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }

        item {
            Text(
                text =  stringResource(R.string.language_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
        }

        item { Divider() }

        items(languages) { language ->
            LanguageRow(
                language = language,
                selected = language.code == selectedLanguageCode,
                onClick = {
                    context.getSharedPreferences("settings", Context.MODE_PRIVATE)
                        .edit()
                        .putString("language", language.code)
                        .apply()

                    onLanguageSelected(language.code)
                    onBack()

                }
            )
            Divider()
        }
    }
}



@Composable
private fun LanguageRow(
    language: AppLanguage,
    selected: Boolean,
    onClick: () -> Unit
) {
    ListItem(
        headlineContent = { Text(text = language.nativeName) },
        supportingContent = { Text(text = language.englishName) },
        trailingContent = {
            RadioButton(
                selected = selected,
                onClick = null
            )
        },
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    )

}




@Preview(showBackground = true)
@Composable
fun AppLanguageScreenPreview() {
    MaterialTheme {
        AppLanguageScreen(
            selectedLanguageCode = "pl",
            onLanguageSelected = {},
            onBack = {}
        )
    }

}
