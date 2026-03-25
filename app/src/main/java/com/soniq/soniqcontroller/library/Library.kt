package com.soniq.soniqcontroller.library

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.soniq.soniqcontroller.R


enum class LibraryDestinations() {
  DISC, USB, CD, LOCAL, ONLINE_RADIOS
}

@Composable
@Preview(showBackground = true, showSystemUi = true)
fun LibraryScreen() {
  var showView by remember { mutableStateOf<LibraryDestinations?>(null) }

  val buttonColors = ButtonDefaults.buttonColors(
    containerColor = Color.Transparent, contentColor = MaterialTheme.colorScheme.onSurface
  )
  val buttonShape = MaterialTheme.shapes.small
  val primaryText = MaterialTheme.typography.titleSmall
  val secondaryText = MaterialTheme.typography.bodySmall
  val imageModifier = Modifier
    .size(120.dp)
    .aspectRatio(16f / 9f)

  if (showView != null) {
    when (showView) {
      LibraryDestinations.DISC -> discLibrary(onBack = { showView = null })
      LibraryDestinations.USB -> usbLibrary(onBack = { showView = null })
      LibraryDestinations.CD -> cdLibrary(onBack = { showView = null })
      LibraryDestinations.LOCAL -> localLibrary(onBack = { showView = null })
      LibraryDestinations.ONLINE_RADIOS -> onlineRadiosLibrary(onBack = { showView = null })
      else -> {}
    }
  } else {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Button(
          onClick = { showView = LibraryDestinations.DISC },
          colors = buttonColors,
          shape = buttonShape
        ) {
          Column() {
            Image(
              painter = painterResource(id = R.drawable.library_placeholder),
              contentDescription = "Library Placeholder",
              modifier = imageModifier
            )
            Text(text = "Disc", style = primaryText)
            Text(text = "Updated today", style = secondaryText)
          }
        }
        Button(
          onClick = { showView = LibraryDestinations.USB },
          colors = buttonColors,
          shape = buttonShape
        ) {
          Column() {
            Image(
              painter = painterResource(id =  R.drawable.library_placeholder),
              contentDescription = "Library Placeholder",
              modifier = imageModifier
            )
            Text(text = "USB", style = primaryText)
            Text(
              text = "Updated 2 days ago", style = secondaryText
            )
          }
        }
      }
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Button(
          onClick = { showView = LibraryDestinations.CD },
          colors = buttonColors,
          shape = buttonShape
        ) {
          Column() {
            Image(
              painter = painterResource(id = R.drawable.library_placeholder),
              contentDescription = "Library Placeholder",
              modifier = imageModifier
            )
            Text(text = "CD", style = primaryText)
            Text(
              text = "Updated 2 days ago", style = secondaryText
            )
          }
        }
        Button(
          onClick = { showView = LibraryDestinations.LOCAL },
          colors = buttonColors,
          shape = buttonShape
        ) {
          Column() {
            Image(
              painter = painterResource(id = R.drawable.library_placeholder),
              contentDescription = "Library Placeholder",
              modifier = imageModifier
            )
            Text(text = "Local", style = primaryText)
            Text(
              text = "Updated yesterday", style = secondaryText
            )
          }
        }
      }
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Button(
          onClick = { showView = LibraryDestinations.ONLINE_RADIOS },
          colors = buttonColors,
          shape = buttonShape
        ) {
          Column() {
            Image(
              painter = painterResource(id = R.drawable.library_placeholder),
              contentDescription = "Library Placeholder",
              modifier = imageModifier
            )
            Text(text = "Online radios", style = primaryText)
            Text(text = "Updated yesterday", style = secondaryText)
          }
        }
      }
    }
  }
}

@Composable
fun discLibrary(onBack: () -> Unit = {}) {
  Column(modifier = Modifier.padding(top = 75.dp)) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      IconButton(onClick = onBack) {
        Icon(
          imageVector = Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back Button"
        )
      }
      Text(text = "Disc", style = MaterialTheme.typography.titleLarge)
      IconButton(onClick = { TODO("Not yet implemented") }) {
        Icon(
          imageVector = Icons.Default.Search,
          contentDescription = "Search Button",
        )
      }
    }
    Column(
      modifier = Modifier
        .verticalScroll(rememberScrollState())
        .padding(bottom = 100.dp)
    ) {
      for (i in 1..100) {
        ListItem(
          headlineContent = { Text(text = "Song Title $i") },
          supportingContent = { Text(text = "Artist $i Name") },
          leadingContent = {
            Image(
              painter = painterResource(id = R.drawable.song_cover),
              contentDescription = "Song Cover Image",
              modifier = Modifier.size(40.dp)
            )
          },
          trailingContent = { Text("2:00") })
      }
    }
  }
}

@Composable
fun usbLibrary(onBack: () -> Unit = {}) {
  Column(modifier = Modifier.padding(top = 75.dp)) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      IconButton(onClick = onBack) {
        Icon(
          imageVector = Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back Button"
        )
      }
      Text(text = "USB", style = MaterialTheme.typography.titleLarge)
      IconButton(onClick = { TODO("Not yet implemented") }) {
        Icon(
          imageVector = Icons.Default.Search,
          contentDescription = "Search Button",
        )
      }
    }
    Column(
      modifier = Modifier
        .verticalScroll(rememberScrollState())
        .padding(bottom = 100.dp)
    ) {
      for (i in 1..100) {
        ListItem(
          headlineContent = { Text(text = "Song Title $i") },
          supportingContent = { Text(text = "Artist $i Name") },
          leadingContent = {
            Image(
              painter = painterResource(id = R.drawable.song_cover),
              contentDescription = "Song Cover Image",
              modifier = Modifier.size(40.dp)
            )
          },
          trailingContent = { Text("2:00") })
      }
    }
  }
}

@Composable
fun cdLibrary(onBack: () -> Unit = {}) {
  Column(modifier = Modifier.padding(top = 75.dp)) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      IconButton(onClick = onBack) {
        Icon(
          imageVector = Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back Button"
        )
      }
      Text(text = "CD", style = MaterialTheme.typography.titleLarge)
      IconButton(onClick = { TODO("Not yet implemented") }) {
        Icon(
          imageVector = Icons.Default.Search,
          contentDescription = "Search Button",
        )
      }
    }
    Column(
      modifier = Modifier
        .verticalScroll(rememberScrollState())
        .padding(bottom = 100.dp)
    ) {
      for (i in 1..100) {
        ListItem(
          headlineContent = { Text(text = "Song Title $i") },
          supportingContent = { Text(text = "Artist $i Name") },
          leadingContent = {
            Image(
              painter = painterResource(id = R.drawable.song_cover),
              contentDescription = "Song Cover Image",
              modifier = Modifier.size(40.dp)
            )
          },
          trailingContent = { Text("2:00") })
      }
    }
  }
}

@Composable
fun localLibrary(onBack: () -> Unit = {}) {
  Column(modifier = Modifier.padding(top = 75.dp)) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      IconButton(onClick = onBack) {
        Icon(
          imageVector = Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back Button"
        )
      }
      Text(text = "Local", style = MaterialTheme.typography.titleLarge)
      IconButton(onClick = { TODO("Not yet implemented") }) {
        Icon(
          imageVector = Icons.Default.Search,
          contentDescription = "Search Button",
        )
      }
    }
    Column(
      modifier = Modifier
        .verticalScroll(rememberScrollState())
        .padding(bottom = 100.dp)
    ) {
      for (i in 1..100) {
        ListItem(
          headlineContent = { Text(text = "Song Title $i") },
          supportingContent = { Text(text = "Artist $i Name") },
          leadingContent = {
            Image(
              painter = painterResource(id = R.drawable.song_cover),
              contentDescription = "Song Cover Image",
              modifier = Modifier.size(40.dp)
            )
          },
          trailingContent = { Text("2:00") })
      }
    }
  }
}

@Composable
fun onlineRadiosLibrary(onBack: () -> Unit = {}) {
  Column(modifier = Modifier.padding(top = 75.dp)) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.SpaceBetween,
      verticalAlignment = Alignment.CenterVertically
    ) {
      IconButton(onClick = onBack) {
        Icon(
          imageVector = Icons.AutoMirrored.Default.ArrowBack, contentDescription = "Back Button"
        )
      }
      Text(text = "Online Radios", style = MaterialTheme.typography.titleLarge)
      IconButton(onClick = { TODO("Not yet implemented") }) {
        Icon(
          imageVector = Icons.Default.Search,
          contentDescription = "Search Button",
        )
      }
    }
    Column(
      modifier = Modifier
        .verticalScroll(rememberScrollState())
        .padding(bottom = 100.dp)
    ) {
      for (i in 1..100) {
        ListItem(
          headlineContent = { Text(text = "Song Title $i") },
          supportingContent = { Text(text = "Artist $i Name") },
          leadingContent = {
            Image(
              painter = painterResource(id = R.drawable.song_cover),
              contentDescription = "Song Cover Image",
              modifier = Modifier.size(40.dp)
            )
          },
          trailingContent = { Text("2:00") })
      }
    }
  }
}