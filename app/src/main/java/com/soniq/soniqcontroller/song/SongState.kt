package com.soniq.soniqcontroller.song

data class SongState(
    val songName: String = "Brak utworu",
    val artistName: String = "Brak wykonawcy",
    val totalTime: Long = 0L,
    val currentTime: Long = 0L,
    val isPlaying: Boolean = false,
    val isFavorite: Boolean = false,
    val repeat: Boolean = false,
    val shuffle: Boolean = false,
    val volume: Float = 0.5f
)