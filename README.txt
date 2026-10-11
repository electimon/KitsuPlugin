KitsuPlugin
===========

Exposes the most recently updated anime in a user's public Kitsu library.
Uses ObjFW and ObjFWTLS, like LastFMPlugin; no API key or password needed.

Build with `make -C plugins-src/KitsuPlugin`, then copy lib52_KitsuPlugin.so
(or the Windows DLL) to your Hanami plugin directory. The root `make plugins`
also builds and installs it automatically.

Copy kitsu.ini.example to configs/kitsu.ini under Hanami's base path and set
username to your profile slug (the part after /users/ in your profile URL).
Alternatively, set user_id to your numeric Kitsu user ID; it takes precedence.
Restart Hanami after changing the configuration.

Configuration in [kitsu]:
  username          Profile slug.
  user_id           Numeric user ID; skips the username lookup.
  status            current (default), planned, completed, on_hold, dropped,
                    or all. Only anime entries are selected, sorted by updatedAt
                    descending. An empty list clears the displayed anime.
  refresh_interval  Seconds between refreshes, default 180, minimum 30.
  api_url           Optional API base URL, default https://kitsu.app/api/edge.
                    Mainly useful for testing against a local fixture server;
                    omit the trailing slash.

Template variables:
  $kitsu::title          Canonical title, falling back to English or romanized.
  $kitsu::image_url      Poster URL, preferring the medium image.
  $kitsu::progress       Episodes watched, including 0.
  $kitsu::episode_count  Total episodes; empty when unknown.
  $kitsu::url            Anime page on Kitsu.
  $kitsu::status         Library status (e.g. current).
  $kitsu::updated_at     Library entry's update timestamp, as returned by Kitsu.
  $kitsu::rating         Personal rating on Kitsu's 2-20 scale; empty if unrated.
  $kitsu::synopsis       Anime synopsis.
  $kitsu::available      1 after loading an entry, otherwise 0.

Example for head.html, story.html, or foot.html:

  <a href="$kitsu::url">
    <img src="$kitsu::image_url" alt="$kitsu::title" width="120">
    <span>$kitsu::title</span>
  </a>
  <p>Episode $kitsu::progress / $kitsu::episode_count</p>

Values are strings escaped for HTML text and quoted HTML attributes. They
are not suitable for direct interpolation into JavaScript or CSS. Refreshes
and response-body reads run asynchronously; template rendering only reads
the cached snapshot. Values start empty (available=0), so the first page may
precede the first API response. Failed requests preserve the last successful
snapshot; a request times out after 20 seconds and can retry on the next tick.
Private entries and content hidden by Kitsu's public API won't be shown.

API references:
  https://hummingbird-me.github.io/api-docs/
  https://github.com/hummingbird-me/kitsu-server/blob/master/app/resources/library_entry_resource.rb
  https://github.com/hummingbird-me/kitsu-server/blob/master/app/resources/user_resource.rb

Regression checks: python3 testing/kitsu_regression.py

NOTE: THIS PLUGIN IS AI GENERATED, see NOTICE.txt for more info
