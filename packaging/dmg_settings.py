# dmgbuild settings for Haven's installer window.
# Run via scripts/build_dmg.sh, which passes: app, background, readme, icon.
import os.path

app = defines["app"]
readme = defines["readme"]
appname = os.path.basename(app)
readmename = os.path.basename(readme)

format = "UDZO"
filesystem = "HFS+"
size = None
files = [app, readme]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")
background = defines["background"]

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

# The 740×560 background (content laid out on a 720×520 grid offset by 10,14) plus the title bar.
window_rect = ((180, 120), (740, 600))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 112

icon_locations = {
    appname: (190, 189),
    "Applications": (550, 189),
    readmename: (630, 419),
}
