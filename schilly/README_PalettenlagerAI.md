Kurz: Ich habe die core‑Skripte und die GUI fürs Palettenlager integriert.

Was ich committet habe (Branch feature/add-palletstorage):
- schilly/scripts/PalettenlagerAI.lua — Manager mit Registration + Basis‑Funktionen (store/withdraw/sell/transfer)
- schilly/scripts/PalettenlagerAI_integration.lua — Integration stub, versucht bei Missionsstart die Placeables zu registrieren
- schilly/gui/storageMenu.xml — einfache GUI Vorlage

Nächste Schritte (empfohlen)
- Ich kann jetzt:
  - a) die vorhandene FS25_PalettenlagerAI.zip entpacken und die fertigen GUI/Script‑Assets in schilly/ai/ (vollständige Integration), oder
  - b) die Skripte weiter ausbauen (Plugin für CoursePlay, detaillierte objectStorage‑Integration, Persistenz im savegame)

Teste lokal:
1) Checkout feature/add-palletstorage
2) Packe das Verzeichnis als Mod‑ZIP (modDesc.xml im Root) und lege es in deinen Mods‑Ordner
3) Starte das Spiel; öffne die Konsole oder Logs, suche nach "[PalettenlagerAI] Registered" Meldungen

Willst du, dass ich jetzt die FS25_PalettenlagerAI.zip aus dem Repo entpacke und die dort enthaltenen, bereits fertigen Skripte/GUIs übernehme und so die Integration komplett mache? (ja/nein)
