# dmgbuild settings: dmgbuild -s dmg_settings.py -D app=... -D bg=... -D readme=... "Ribbon" out.dmg
import os.path

app = defines["app"]
readme = defines["readme"]
files = [app, readme]
symlinks = {"Applications": "/Applications"}
background = defines["bg"]
icon = defines.get("icon")
icon_locations = {
    os.path.basename(app): (165, 185),
    "Applications": (495, 185),
    os.path.basename(readme): (566, 360),
}
# With "show hidden files" on in Finder, the disk's support files would land on top of the layout.
# Park them well outside the window so the install screen stays clean either way.
for i, hidden in enumerate([".background", ".VolumeIcon.icns", ".DS_Store", ".fseventsd", ".Trashes", ".TemporaryItems"]):
    icon_locations[hidden] = (120 + i * 110, 1200)
window_rect = ((200, 140), (660, 440))
default_view = "icon-view"
icon_size = 96
text_size = 12
format = "UDZO"
filesystem = "HFS+"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = "auto"
arrange_by = None
hide_extensions = [os.path.basename(app)]
