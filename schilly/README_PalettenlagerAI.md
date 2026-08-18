Enhanced PalettenlagerAI

Was ist neu?
- Cross‑farm transfer stub: PalettenlagerAI.transferToFarm(fromId, targetFarmId, amount)
  - Tries to find a local placeable owned by the target farm and stores directly.
  - If none found, logs a placeholder message. Real cross‑farm transfer requires a remote receiver (RPC) which can be added later.
- Distribution helper: PalettenlagerAI.distribute(fromId, targetFilter, amountPerTarget)
  - Distributes items to other registered storages (or factories if filter selects them).
- Utility to find placeables by xml pattern (useful to find factory placeables by name)

Next recommended steps (I can do these for you):
1) Complete multiplayer RPC: implement remote handler so a player on another client/server can accept the transfer automatically.
2) Wire the GUI (schilly/gui/storageMenu.xml) to the PalettenlagerAI methods (button callbacks + list population).
3) Persist storage levels in the savegame (save/load functions).
4) Integrate the full FS25_PalettenlagerAI package from the repo (it contains more advanced GUI components and scripts) — I can unpack and merge those now.

If you want, I will now:
- Unpack and merge FS25_PalettenlagerAI.zip contents into schilly/ (recommended),
- Wire up the GUI so buttons call the PalettenlagerAI functions,
- Implement simple save/load for the current level values.

Reply "merge and wire GUI" to proceed and I'll commit the changes to feature/add-palletstorage.