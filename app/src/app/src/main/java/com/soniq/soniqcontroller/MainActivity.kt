package com.soniq.soniqcontroller
import com.soniq.soniqcontroller.ui.theme.SoniqTheme
import android.os.Bundle
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


enum class Destination(val route: String, val label: String, val icon: ImageVector) {
  SONG("song", "Song", Icons.Outlined.MusicNote), LIBRARY(
    "library", "Library", Icons.Outlined.Folder
  ),
  SETTINGS("settings", "Settings", Icons.Outlined.Settings)

}

//@Composable
//fun SettingsScreen() {
//  Box(
//    modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center
//  ) {
//    Text(text = "Settings Screen")
//  }
//}

@Composable
fun NavigationBarBottom(modifier: Modifier = Modifier,highContrast: Boolean, onHighContrastChange: (Boolean) -> Unit) {
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
              destination.icon, contentDescription = destination.label
            )
          }, label = { Text(destination.label) })
        }
      }
    }) { contentPadding ->
    AppNavHost(navController, startDestination, modifier = Modifier.padding(contentPadding), highContrast = highContrast, onHighContrastChange = onHighContrastChange)
  }
}

@Composable
fun AppNavHost(
    navController: NavHostController,
    startDestination: Destination,
    modifier: Modifier = Modifier,
    highContrast: Boolean,
    onHighContrastChange: (Boolean) -> Unit
) {
    NavHost(
        navController = navController,
        startDestination = startDestination.route,
        modifier = modifier
    ) {


        Destination.entries.forEach { destination ->
            composable(destination.route) {
                when (destination) {
                    Destination.SONG -> SongScreen()
                    Destination.LIBRARY -> LibraryScreen()
                    Destination.SETTINGS -> SettingsScreen(
                        onAppearanceClick = {
                            navController.navigate("appearance")
                        }
                    )
                }
            }
        }


        composable("appearance") {
            AppearanceScreen(
                highContrast = highContrast,
                onHighContrastChange = onHighContrastChange,
                onBack = { navController.popBackStack() }
            )
        }
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            var highContrast by rememberSaveable { mutableStateOf(false) }

            SoniqTheme(highContrast = highContrast) {
                NavigationBarBottom(
                    highContrast = highContrast,
                    onHighContrastChange = { highContrast = it }
                )
            }

        }
    }
}
