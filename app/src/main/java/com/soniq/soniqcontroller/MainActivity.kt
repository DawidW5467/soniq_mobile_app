package com.soniq.soniqcontroller
import android.app.Activity
import android.content.Context
import com.soniq.soniqcontroller.ui.theme.SoniqTheme
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import com.soniq.soniqcontroller.data.SettingsDataStore
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.soniq.soniqcontroller.library.LibraryScreen
import com.soniq.soniqcontroller.settings.AppearanceScreen
import com.soniq.soniqcontroller.song.SongScreen
import com.soniq.soniqcontroller.settings.SettingsScreen
import com.soniq.soniqcontroller.settings.SettingsScreen
import com.soniq.soniqcontroller.settings.SystemInfoScreen
import com.soniq.soniqcontroller.settings.AppLanguage
import  androidx.annotation.StringRes
import androidx.appcompat.app.AppCompatActivity
import com.soniq.soniqcontroller.settings.AppLanguageScreen
import androidx.compose.ui.res.stringResource
import androidx.core.os.LocaleListCompat
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import com.soniq.soniqcontroller.remote.RemoteWebSocketClient
import com.soniq.soniqcontroller.settings.PairDeviceScreen
import com.soniq.soniqcontroller.ui.settings.FontScale
import kotlinx.coroutines.launch

enum class Destination(val route: String, @StringRes val labelRes: Int, val icon: ImageVector) {
  SONG("song", R.string.nav_song, Icons.Outlined.MusicNote), LIBRARY(
    "library", R.string.nav_library, Icons.Outlined.Folder
  ),
  SETTINGS("settings", R.string.nav_settings, Icons.Outlined.Settings)

}


@Composable
fun NavigationBarBottom(modifier: Modifier = Modifier,highContrast: Boolean, onHighContrastChange: (Boolean) -> Unit, replaceIconsWithText: Boolean, onReplaceIconsChange: (Boolean) -> Unit, selectedLanguage: String,onLanguageChange: (String) -> Unit, fontScale: FontScale, onFontScaleChange: (FontScale) -> Unit ) {
  val navController = rememberNavController()
  val startDestination = Destination.SONG
  var selectedDestination by rememberSaveable { mutableIntStateOf(startDestination.ordinal) }

  Scaffold(
    modifier = modifier, bottomBar = {
      NavigationBar(windowInsets = NavigationBarDefaults.windowInsets) {
        Destination.entries.forEachIndexed { index, destination ->
          NavigationBarItem(selected = selectedDestination == index, onClick = {
            navController.navigate(route = destination.route)
            selectedDestination = index
          }, icon = {
            Icon(
              destination.icon, contentDescription = stringResource(destination.labelRes)
            )
          }, label = { Text(stringResource(destination.labelRes)) })
        }
      }
    }) { contentPadding ->
    AppNavHost(navController, startDestination, modifier = Modifier.padding(contentPadding), highContrast = highContrast, onHighContrastChange = onHighContrastChange, replaceIconsWithText = replaceIconsWithText, onReplaceIconsChange = onReplaceIconsChange,selectedLanguage=selectedLanguage,onLanguageChange=onLanguageChange,fontScale = fontScale, onFontScaleChange = onFontScaleChange)
  }
}

@Composable
fun AppNavHost(
    navController: NavHostController,
    startDestination: Destination,
    modifier: Modifier = Modifier,
    highContrast: Boolean,
    onHighContrastChange: (Boolean) -> Unit,
    replaceIconsWithText: Boolean,
    onReplaceIconsChange: (Boolean) -> Unit,
    selectedLanguage: String,
    onLanguageChange: (String) -> Unit,
    fontScale: FontScale,
    onFontScaleChange: (FontScale) -> Unit
) {
    NavHost(
        navController = navController,
        startDestination = startDestination.route,
        modifier = modifier
    ) {


        Destination.entries.forEach { destination ->
            composable(destination.route) {
                when (destination) {
                    Destination.SONG -> SongScreen( replaceIconsWithText = replaceIconsWithText )
                    Destination.LIBRARY -> LibraryScreen()
                    Destination.SETTINGS -> SettingsScreen(
                        onPairClick = {
                            navController.navigate("pairDevice")
                        },
                        onAppearanceClick = {
                            navController.navigate("appearance")
                        },
                        onSystemClick = {
                            navController.navigate("systemInfo")
                        },
                        onLanguageClick = {
                            navController.navigate("appLanguage")
                        }
                    )
                }
            }
        }


        composable("appearance") {
            AppearanceScreen(
                highContrast = highContrast,
                onHighContrastChange = onHighContrastChange,
                replaceIconsWithText = replaceIconsWithText,
                onReplaceIconsChange = onReplaceIconsChange,
                fontScale = fontScale,
                onFontScaleChange = onFontScaleChange,
                onBack = { navController.popBackStack() }
            )
        }

        composable("systemInfo"){
            SystemInfoScreen(
                onBack = { navController.popBackStack() }
            )
        }

        composable("appLanguage") {
            AppLanguageScreen(
                selectedLanguageCode = selectedLanguage,
                onLanguageSelected = { code ->
                    onLanguageChange(code)
                    navController.popBackStack()
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable("pairDevice") {

            val context = LocalContext.current

            PairDeviceScreen(
                onBack = { navController.popBackStack() },

                onPaired = { token, code ->

                    RemoteWebSocketClient.connect(
                        ip = "192.168.1.12",   // ← IP Fluttera
                        port = 8787,
                        token = token,
                        code = code,
                        onConnected = {

                            Toast.makeText(
                                context,
                                "Połączono z Flutter!",
                                Toast.LENGTH_LONG
                            ).show()

                            // 🔥 PRZEJŚCIE DO SONG
                            navController.navigate(Destination.SONG.route) {
                                popUpTo(Destination.SETTINGS.route) {
                                    inclusive = false
                                }
                                launchSingleTop = true
                            }
                        },
                        onError = {
                            Toast.makeText(
                                context,
                                "Błąd: $it",
                                Toast.LENGTH_LONG
                            ).show()
                        }
                    )
                }
            )
        }

    }
}

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {


        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val savedLanguage = prefs.getString("language", "pl")!!

        AppCompatDelegate.setApplicationLocales(
            LocaleListCompat.forLanguageTags(savedLanguage)
        )

        super.onCreate(savedInstanceState)

        enableEdgeToEdge()

        setContent {

            val context = LocalContext.current
            val scope = rememberCoroutineScope()


            val settingsStore = remember {
                SettingsDataStore(context)
            }

            val highContrast by settingsStore.highContrast
                .collectAsState(initial = false)

            val replaceIconsWithText by settingsStore.replaceIcons
                .collectAsState(initial = false)

            val fontScale by settingsStore.fontScale
                .collectAsState(initial = FontScale.NORMAL)


            var selectedLanguage by rememberSaveable {
                mutableStateOf(savedLanguage)
            }


            LaunchedEffect(selectedLanguage) {
                prefs.edit()
                    .putString("language", selectedLanguage)
                    .apply()

                AppCompatDelegate.setApplicationLocales(
                    LocaleListCompat.forLanguageTags(selectedLanguage)
                )

                Toast.makeText(
                    context,
                    "Language changed to $selectedLanguage",
                    Toast.LENGTH_SHORT
                ).show()
            }


            SoniqTheme(
                highContrast = highContrast,
                fontScale = fontScale
            ) {
                NavigationBarBottom(
                    highContrast = highContrast,
                    onHighContrastChange = {
                        scope.launch {
                            settingsStore.setHighContrast(it)
                        }
                    },
                    replaceIconsWithText = replaceIconsWithText,
                    onReplaceIconsChange = {
                        scope.launch {
                            settingsStore.setReplaceIcons(it)
                        }
                    },
                    selectedLanguage = selectedLanguage,
                    onLanguageChange = { selectedLanguage = it },
                    fontScale = fontScale,
                    onFontScaleChange = {
                        scope.launch {
                            settingsStore.setFontScale(it)
                        }
                    }
                )
            }
        }
    }
}