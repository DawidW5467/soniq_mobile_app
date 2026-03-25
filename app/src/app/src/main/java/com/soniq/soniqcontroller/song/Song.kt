package com.soniq.soniqcontroller.song

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import com.soniq.soniqcontroller.R
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeMute
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProgressIndicatorDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

const val songName = "Let It Happen"
const val artistName = "Tame Impala"
const val totalTime = 150000L

enum class ButtonType(
  val icon: ImageVector, val description: String, val isPrimary: Boolean = false
) {
  PREVIOUS(Icons.Default.SkipPrevious, "Previous"), PLAY(
    Icons.Default.PlayArrow, "Play", true
  ),
  NEXT(Icons.Default.SkipNext, "Next"), REPEAT(
    Icons.Default.Repeat, "Repeat"
  ),
  STOP(Icons.Default.Stop, "Stop"), SHUFFLE(
    Icons.Default.Shuffle, "Shuffle"
  )
}

/**
 * Represents the Song Screen UI.
 */
@Composable
@Preview(showBackground = true, showSystemUi = true)
fun SongScreen() {
  var isPlaying by remember { mutableStateOf(false) }
  var progress by remember { mutableStateOf(0f) }
  var currentTime by remember { mutableStateOf(0L) }

  LaunchedEffect(isPlaying) {
    while (isPlaying && progress < 1f) {
      delay(200L)
      progress += calculateProgress(200L, totalTime)
      currentTime += 200L
    }
  }

  Column(
    modifier = Modifier
      .fillMaxSize()
      .padding(16.dp, 48.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Top
  ) {
    SongUI()
    Spacer(modifier = Modifier.size(32.dp))
    SongProgressUI(progress, getTimeString(currentTime), getTimeString(totalTime))
    Spacer(modifier = Modifier.size(20.dp))
    ButtonsUI(
      onPlay = { isPlaying = true },
      onPause = { isPlaying = false },
    )
    Spacer(modifier = Modifier.size(40.dp))
    VolumeUI()
  }
}

@Composable
fun SongUI() {
  Column(
    verticalArrangement = Arrangement.spacedBy(8.dp),
    horizontalAlignment = Alignment.CenterHorizontally
  ) {
    Image(
      painter = painterResource(id = R.drawable.song_cover),
      contentDescription = "Song Screen Image",
      modifier = Modifier
        .requiredSize(300.dp)
        .aspectRatio(1f)
    )
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(start = 30.dp, end = 10.dp),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      Column() {
        Text(
          text = songName,
          fontSize = MaterialTheme.typography.headlineLarge.fontSize,
          fontWeight = FontWeight.Bold,
          color = MaterialTheme.colorScheme.secondary
        )
        Spacer(modifier = Modifier.size(2.dp))
        HorizontalDivider(
          modifier = Modifier.width((songName.length * 15 + 10).dp),
          color = MaterialTheme.colorScheme.outlineVariant
        )
        Spacer(modifier = Modifier.size(8.dp))
        Text(
          text = artistName,
          fontSize = MaterialTheme.typography.bodyLarge.fontSize,
          color = MaterialTheme.colorScheme.onSurfaceVariant
        )
      }
      FavoriteButton()
    }
  }
}

@Composable
fun SongProgressUI(progress: Float, currentTime: String, totalTime: String) {
  val animatedProgress by animateFloatAsState(
    targetValue = progress,
    animationSpec = ProgressIndicatorDefaults.ProgressAnimationSpec,
  )
  Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Text(text = currentTime)
    LinearProgressIndicator(
      progress = { animatedProgress }, modifier = Modifier.weight(1f)
    )
    Text(text = totalTime)
  }
}

@Composable
fun ButtonsUI(onPlay: () -> Unit, onPause: () -> Unit) {
  LazyVerticalGrid(
    columns = GridCells.Fixed(3),
    horizontalArrangement = Arrangement.spacedBy(36.dp),
    verticalArrangement = Arrangement.spacedBy(20.dp),
  ) {
    items(ButtonType.entries.size) {
      val buttonType = ButtonType.entries[it]
      Button(
        onClick = {
          when (buttonType) {
            ButtonType.PLAY -> onPlay()
            ButtonType.STOP -> onPause()
            ButtonType.NEXT -> goToNextSong()
            ButtonType.PREVIOUS -> goToPreviousSong()
            ButtonType.REPEAT -> loopSong()
            ButtonType.SHUFFLE -> shuffleSongs()
          }
        },
        modifier = Modifier.padding(8.dp, 4.dp),
        shape = MaterialTheme.shapes.medium,
        colors = if (buttonType.isPrimary) ButtonDefaults.buttonColors(
          containerColor = MaterialTheme.colorScheme.primary,
          contentColor = MaterialTheme.colorScheme.onPrimary
        ) else ButtonDefaults.buttonColors(
          containerColor = MaterialTheme.colorScheme.surfaceVariant,
          contentColor = MaterialTheme.colorScheme.onSurfaceVariant
        ),

        ) {
        Icon(
          imageVector = buttonType.icon,
          contentDescription = buttonType.description,
          modifier = Modifier.size(32.dp)
        )
      }
    }
  }
}

@Composable
fun VolumeUI() {
  var volumeLevel by remember { mutableStateOf(0.5f) }
  var previousVolumeLevel by remember { mutableStateOf(volumeLevel) }
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(20.dp),
    modifier = Modifier.fillMaxWidth()
  ) {
    Button(
      onClick = {
        if (volumeLevel == 0f) {
          volumeLevel = previousVolumeLevel
        } else {
          previousVolumeLevel = volumeLevel
          volumeLevel = 0f
        }
      },
      shape = MaterialTheme.shapes.medium,
      colors = ButtonDefaults.buttonColors(
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant
      ),
      modifier = Modifier.size(48.dp)

    ) {
      Icon(
        imageVector = if (volumeLevel == 0f) Icons.AutoMirrored.Default.VolumeMute else Icons.AutoMirrored.Default.VolumeUp,
        contentDescription = if (volumeLevel == 0f) "Unmute" else "Mute",
        modifier = Modifier.requiredSize(24.dp)
      )
    }
    Slider(
      value = volumeLevel, onValueChange = { volumeLevel = it },
    )
  }
}

@Composable
fun FavoriteButton() {
  var isFavorite by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(
    targetValue = if (isFavorite) 1.2f else 1f, animationSpec = tween(durationMillis = 300)
  )

  IconButton(
    onClick = { isFavorite = !isFavorite },
  ) {
    Icon(
      imageVector = if (isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
      contentDescription = if (!isFavorite) "Add to Favorites" else "Remove from Favorites",
      tint = MaterialTheme.colorScheme.primary,
      modifier = Modifier.graphicsLayer(
        scaleX = scale, scaleY = scale
      )
    )
  }
}

fun calculateProgress(currentTime: Long, totalTime: Long): Float {
  return currentTime.toFloat() / totalTime.toFloat()
}

fun getTimeString(milliseconds: Long): String {
  val totalSeconds = milliseconds / 1000
  val minutes = totalSeconds / 60
  val seconds = totalSeconds % 60
  return String.format("%d:%02d", minutes, seconds)
}

fun goToPreviousSong() {
  TODO("Not yet implemented")
}

fun goToNextSong() {
  TODO("Not yet implemented")
}

fun loopSong() {
  TODO("Not yet implemented")
}

fun shuffleSongs() {
  TODO("Not yet implemented")
}