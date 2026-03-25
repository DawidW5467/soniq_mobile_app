import 'package:flutter/widgets.dart';

/// Prosta lokalizacja bez gen_l10n: wystarcza dla kiosku/offline.
///
/// Użycie:
///   final t = AppStrings.of(context);
///   Text(t.get('settings'))
class AppStrings {
  final Locale locale;

  AppStrings(this.locale);

  static AppStrings of(BuildContext context) {
    final loc = Localizations.localeOf(context);
    return AppStrings(loc);
  }

  static const Map<String, Map<String, String>> values = {
    'pl': {
      // Common
      'appTitle': 'Soniq',
      'loading': 'Ładowanie…',
      'refresh': 'Odśwież',
      'cancel': 'Anuluj',
      'save': 'Zapisz',
      'create': 'Utwórz',
      'createAndAdd': 'Utwórz i dodaj',
      'options': 'Opcje',
      'search': 'Szukaj',
      'noResults': 'Brak wyników',
      'unknownArtist': 'Nieznany artysta',
      'unknownAlbum': 'Nieznany album',

      // Sources
      'selectSource': 'Wybierz źródło muzyki',
      'musicSources': 'Źródła muzyki',
      'music': 'Muzyka',
      'downloads': 'Pobrane',
      'cd': 'Płyta CD',
      'usb': 'Pendrive USB',
      'network': 'Serwer sieciowy',
      'local': 'Lokalny katalog',

      // Player / Playback
      'trackList': 'Lista utworów',
      'lyrics': 'Tekst',
      'visualizer': 'Wizualizer',
      'noPlaylistLoaded': 'Brak załadowanej playlisty',
      'lastPlayed': 'Ostatnio odtwarzane',
      'favorites': 'Ulubione',
      'noFavorites': 'Brak ulubionych utworow.',
      'home': 'Strona główna',
      'loadingCd': 'Ładowanie CD…',
      'loadingCdLong': 'Ładowanie CD Audio — może to chwilę potrwać…',
      'cdLoaded': 'CD załadowane! Używam zwiększonego buforowania dla płynnego odtwarzania.',

      // Playlists
      'playlists': 'Playlisty',
      'playlist': 'Playlista',
      'addToPlaylist': 'Dodaj do playlisty',
      'addedToPlaylist': 'Dodano do playlisty',
      'newPlaylist': 'Nowa playlista',
      'playlistName': 'Nazwa playlisty',
      'play': 'Odtwórz',
      'delete': 'Usuń',
      'renamePlaylist': 'Zmień nazwę',
      'noPlaylists': 'Brak playlist',
      'itemsCount': 'pozycji',
      'removeFromPlaylist': 'Usuń z playlisty',
      'emptyPlaylist': 'Pusta playlista',
      'playlistNotFound': 'Nie znaleziono playlisty',
      'dedupeByPath': 'Usuń duplikaty (wg ścieżki)',
      'sortDirection': 'Kierunek sortowania',
      'sortedView': 'Widok sort.',
      'orderView': 'Kolejność',
      'apply': 'Zastosuj',
      'sort_addedAt': 'Dodane',
      'sort_fileName': 'Nazwa pliku',
      'sort_title': 'Tytuł',
      'sort_artist': 'Artysta',
      'sort_album': 'Album',

      // Library
      'library_all': 'Biblioteka',
      'albums': 'Albumy',
      'artists': 'Artyści',
      'tracks': 'Utwory',
      'noAlbums': 'Brak albumów.',
      'noArtists': 'Brak artystów.',
      'noTracks': 'Brak utworów.',
      'tracksCount': 'utworów',
      'playAlbum': 'Odtwórz album',
      'playAll': 'Odtwórz wszystko',
      'searchLibraryHint': 'Szukaj (utwór/album/artysta)…',

      // History
      'history': 'Historia',
      'clearHistory': 'Wyczyść historię',

      // Tracks screen
      'searchTracksHint': 'Szukaj utworu / artysty / albumu…',
      'loadingTrack': 'Ładowanie utworu…',

      // Settings
      'settings': 'Ustawienia',
      'highContrast': 'Wysoki kontrast',
      'polishLanguage': 'Język polski',
      'switchToEnglishHint': 'Odznacz aby zmienić na angielski',
      'fontSize': 'Wielkość czcionki',
      'remoteControl': 'Zdalne sterowanie',
      'remoteHint': 'Włącz i zeskanuj QR poniżej',
      'remoteDisabled': 'Zdalne sterowanie jest wyłączone.',
      'startingServer': 'Uruchamiam serwer…',
      'wsAddress': 'Adres WebSocket:',
      'pairCode': 'Kod parowania (6 cyfr):',
      'audioOutput': 'Wyjście audio',
      'audioDevice': 'Urządzenie audio',
      'shuffle': 'Losowo',
      'repeat': 'Powtarzanie',
      'songTitleFallback': 'Tytuł utworu',
      'language': 'Język',
      'languageHint': 'Przełącz na język polski',
      'simpleControls': 'Proste opisy przycisków',
      'simpleControlsHint': 'Zamiast ikon pokaż tekst: stop, następny itp.',
      'brightness': 'Jasność',
      'controlShuffle': 'Losowo',
      'controlPrevious': 'Poprzedni',
      'controlPlay': 'Odtwórz',
      'controlPause': 'Pauza',
      'controlNext': 'Następny',
      'controlRepeat': 'Powtórz',
      'controlRepeatOne': 'Powtórz 1',
      'controlStop': 'Stop',

      // TrackPicker
      'pickTracks': 'Wybierz utwory',
      'retry': 'Spróbuj ponownie',
      'scanError': 'Błąd podczas skanowania źródeł:',
      'noTracksInSources': 'Brak utworów w wybranych źródłach.',
      'refreshTooltip': 'Odśwież',
      'searchByNamePathSource': 'Szukaj po nazwie/ścieżce/źródle…',
      'selectedCount': 'Zaznaczone',
      'selectAllVisible': 'Zaznacz wszystko (widoczne)',
      'addN': 'Dodaj',
      'noLyrics': 'Brak tekstu w metadanych dla tego utworu.',
      'noLastPlayed': 'Najpierw wybierz i odtwórz utwór.',
    },
    'en': {
      // Common
      'appTitle': 'Soniq',
      'loading': 'Loading…',
      'refresh': 'Refresh',
      'cancel': 'Cancel',
      'save': 'Save',
      'create': 'Create',
      'createAndAdd': 'Create & add',
      'options': 'Options',
      'search': 'Search',
      'noResults': 'No results',
      'unknownArtist': 'Unknown artist',
      'unknownAlbum': 'Unknown album',

      // Sources
      'selectSource': 'Select music source',
      'musicSources': 'Music sources',
      'music': 'Music',
      'downloads': 'Downloads',
      'cd': 'Audio CD',
      'usb': 'USB drive',
      'network': 'Network share',
      'local': 'Local folder',

      // Player / Playback
      'trackList': 'Track list',
      'lyrics': 'Lyrics',
      'visualizer': 'Visualizer',
      'noPlaylistLoaded': 'No playlist loaded',
      'lastPlayed': 'Last played',
      'home': 'Homepage',
      'favorites': 'Favorites',
      'noFavorites': 'No favorite tracks yet.',
      'loadingCd': 'Loading CD…',
      'loadingCdLong': 'Loading audio CD — this may take a moment…',
      'cdLoaded': 'CD loaded! Using increased buffering for smooth playback.',

      // Playlists
      'playlists': 'Playlists',
      'playlist': 'Playlist',
      'addToPlaylist': 'Add to playlist',
      'addedToPlaylist': 'Added to playlist',
      'newPlaylist': 'New playlist',
      'playlistName': 'Playlist name',
      'play': 'Play',
      'delete': 'Delete',
      'renamePlaylist': 'Rename',
      'noPlaylists': 'No playlists',
      'itemsCount': 'items',
      'removeFromPlaylist': 'Remove from playlist',
      'emptyPlaylist': 'Empty playlist',
      'playlistNotFound': 'Playlist not found',
      'dedupeByPath': 'Remove duplicates (by path)',
      'sortDirection': 'Sort direction',
      'sortedView': 'Sorted view',
      'orderView': 'Order',
      'apply': 'Apply',
      'sort_addedAt': 'Added',
      'sort_fileName': 'File name',
      'sort_title': 'Title',
      'sort_artist': 'Artist',
      'sort_album': 'Album',

      // Library
      'library_all': 'Library',
      'albums': 'Albums',
      'artists': 'Artists',
      'tracks': 'Tracks',
      'noAlbums': 'No albums.',
      'noArtists': 'No artists.',
      'noTracks': 'No tracks.',
      'tracksCount': 'tracks',
      'playAlbum': 'Play album',
      'playAll': 'Play all',
      'searchLibraryHint': 'Search (track/album/artist)…',

      // History
      'history': 'History',
      'clearHistory': 'Clear history',

      // Tracks screen
      'searchTracksHint': 'Search track / artist / album…',
      'loadingTrack': 'Loading track…',

      // Settings
      'settings': 'Settings',
      'highContrast': 'High contrast',
      'polishLanguage': 'Polish language',
      'switchToEnglishHint': 'Turn off to switch to English',
      'fontSize': 'Font size',
      'remoteControl': 'Remote control',
      'remoteHint': 'Enable and scan the QR below',
      'remoteDisabled': 'Remote control is disabled.',
      'startingServer': 'Starting server…',
      'wsAddress': 'WebSocket address:',
      'pairCode': 'Pairing code (6 digits):',
      'audioOutput': 'Audio output',
      'audioDevice': 'Audio device',
      'shuffle': 'Shuffle',
      'repeat': 'Repeat',
      'songTitleFallback': 'Song title',
      'language': 'Language',
      'languageHint': 'Switch to Polish',
      'simpleControls': 'Simple control labels',
      'simpleControlsHint': 'Show text like stop/next instead of icons.',
      'brightness': 'Brightness',
      'controlShuffle': 'Shuffle',
      'controlPrevious': 'Previous',
      'controlPlay': 'Play',
      'controlPause': 'Pause',
      'controlNext': 'Next',
      'controlRepeat': 'Repeat',
      'controlRepeatOne': 'Repeat 1',
      'controlStop': 'Stop',

      // TrackPicker
      'pickTracks': 'Select tracks',
      'retry': 'Try again',
      'scanError': 'Error while scanning sources:',
      'noTracksInSources': 'No tracks in selected sources.',
      'refreshTooltip': 'Refresh',
      'searchByNamePathSource': 'Search by name/path/source…',
      'selectedCount': 'Selected',
      'selectAllVisible': 'Select all (visible)',
      'addN': 'Add',
      'noLyrics': 'No lyrics found in metadata for this track.',
      'noLastPlayed': 'Select and play a track first.',
    },
  };

  String get(String key) {
    final lang = locale.languageCode;
    return values[lang]?[key] ?? values['en']?[key] ?? key;
  }
}
