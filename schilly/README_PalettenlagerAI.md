I moved the AI integration forward:

- Implemented network transfer event (schilly/scripts/events/PalettenlagerTransferEvent.lua)
- Added save/load support inside PalettenlagerAI (save to simple xml file in savegame)
- Added a basic StorageMenu script (schilly/scripts/StorageMenu.lua) that wires the GUI layout to the PalettenlagerAI functions (basic interactions)

Next steps I will run if you confirm:
- Hook StorageMenu buttons to the GUI (element callbacks) — many game versions require explicit binding; I can add those bindings.
- Move assets into schilly/(i3d|textures|gui) and fix XML paths.

If you want me to proceed with final bindings + asset move, reply "proceed assets+bindings".