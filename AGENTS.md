# Agent Development Log

This document tracks significant changes, features, and improvements made to the tvpass-roku IPTV player application through AI agent assistance.

---

## Project Overview

**tvpass-roku** is a Roku channel application for streaming live IPTV channels. It fetches M3U playlists and XMLTV Electronic Program Guide (EPG) data from tvpass.org and provides a user-friendly interface for browsing and watching live TV channels.

### Key Features
- M3U playlist parsing and channel loading
- XMLTV EPG integration with current program information
- Background video playback while browsing channels
- Automatic EPG refresh (5-minute intervals)
- HD stream preference (auto-converts SD to HD URLs)
- Channel list with now-playing information
- Focus-based UI animations

---

## Recent Changes

### November 8, 2025 - Initial Project Setup & Background Playback Fix

**Commit:** `1a45fde` - "Remove showing loading label when back button is pressed"

#### What Changed
This commit represents the initial working version of the application with a critical UX improvement for background playback mode.

#### Key Implementations

**1. Background Playback Enhancement**
- Fixed issue where loading label would appear when returning to channel list via back button
- Implemented smooth transition between full-screen video and channel browsing
- Background video continues playing with proper overlay while browsing channels
- Loading label now only shown during actual data loading operations

**2. Core Application Structure**
- `MainScene.brs/xml`: Main application logic with video player and channel list
- `SimpleChannelItem.brs/xml`: Custom channel list item renderer with EPG display
- `ChannelItem.brs/xml`: Alternative channel item with poster support
- `LoadPlaylistTask.brs/xml`: Asynchronous M3U playlist fetching
- `LoadScheduleTask.brs/xml`: Asynchronous XMLTV EPG data fetching
- `main.brs`: Application entry point

**3. EPG Integration**
- Parses XMLTV format EPG data from tvpass.org
- Matches current programs to channels via `tvg-id`
- Displays "now playing" information in channel list
- Smart time filtering (shows programs starting within 5 minutes)
- Includes program subtitles and descriptions when available
- 5-minute cache to reduce unnecessary EPG refreshes

**4. Playlist Management**
- M3U playlist parser with support for:
  - Channel titles
  - `tvg-id` for EPG matching
  - `tvg-logo` for channel logos
- Automatic SD to HD stream conversion
- Timestamp-based URL parameters to prevent caching
- Refresh capability via options/star button (*)

**5. User Interface**
- Dark theme with focused item highlighting (blue accent color)
- Smooth opacity transitions for focus states
- Channel list with now-playing metadata display
- Full-screen video playback
- Video overlay when browsing channels in background playback mode
- Position memory - returns to last selected channel

**6. Key Controls**
- **Back button**: Return to channel list (enables background playback)
- **Options/Star button (*)**: Refresh channel playlist
- **Up/Down**: Navigate channel list
- **OK/Select**: Play selected channel

**7. Technical Features**
- HTTP request caching prevention with timestamp parameters and headers
- 10-second timeout for network requests
- Error handling for playlist and EPG loading failures
- Graceful degradation (continues without EPG if fetch fails)
- HLS stream format support
- Automatic fresh connection for HTTP requests

#### Files Added (16 files, 861 insertions)
- Components: 10 files (BrightScript + XML interfaces)
- Images: 4 files (HD/SD icons and splash screens)
- Source: 1 main entry point
- Manifest: 1 configuration file

---

## Architecture Notes

### Component Structure
```
MainScene (root)
├── LoadingLabel - Status messages
├── ChannelList - Vertical list of channels
├── VideoPlayer - HLS video playback
├── VideoOverlay - Dark overlay for background playback
└── ChannelListBackground - Black background for channel list
```

### Data Flow
1. App starts → Load M3U playlist
2. Playlist loaded → Load XMLTV EPG
3. EPG parsed → Match programs to channels by tvg-id
4. Display channel list with now-playing info
5. User selects channel → Full-screen playback
6. Back button → Background playback + channel list overlay
7. EPG auto-refreshes every 5 minutes

### Network Requests
- Playlist URL: `https://tvpass.org/playlist/m3u?t=[timestamp]`
- EPG URL: `https://tvpass.org/epg.xml?t=[timestamp]`
- Cache-control headers: `no-cache, no-store, must-revalidate`
- User-Agent: `Roku/IPTV-Client`

---

## Known Behaviors

### EPG Matching
- Channels without `tvg-id` won't display program information
- EPG data filtered to current/upcoming programs (5-minute window)
- Mismatches logged for first 5 channels for debugging

### Video Playback
- SD streams automatically converted to HD (URL path replacement)
- HLS format required
- Video continues in background when browsing channel list
- Full opacity maintained during background playback for proper visibility

### Refresh Logic
- Playlist: Manual refresh via * button
- EPG: Auto-refresh every 5 minutes or when returning from video
- Schedule check happens before EPG fetch to prevent unnecessary updates

---

## Future Considerations

Potential areas for enhancement (not yet implemented):
- Search/filter functionality for channel list
- Favorites/channel grouping
- Grid-based EPG view
- Parental controls
- Resume playback position
- Multi-day EPG data
- Channel logo fallbacks
- Network error retry logic
- Analytics/usage tracking
