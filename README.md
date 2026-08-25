# yt-dlps

yt-dlp is a great open source tool developed to download YouTube playlists. This project is simply a bash wrapper to this tool that allows the user to automate many actions related to keeping and updating a media library:
- Download multiple playlists at once
- Sorting tracks into folders
- Encoding tracks with music genre metadata
- Monitoring the progress in a minimal CLI
- Speeding up subsequent runs by avoiding downloads of non updated playlists.

![yt-dlps Utils](demo/yt-dlps-demo.gif)

## Requirements

- Bash 4.3+
- yt-dlp
- FFmpeg
- jq
- Firefox
- Deno 2.3+
