# NexQ Suite Launcher

A single Windows cockpit for the Omar interview stack:

- **NexQ Fixed** — launch the local NexQ development app.
- **3V0L Interview** — launch the live interview brain.
- **Interview Mode** — starts both, opens the Notion live cheat sheet, then opens the LAN remote display.
- **Notion memory** — Career Knowledge Base, Interview Intelligence Hub, and Interview Question Router.
- **LAN tools** — remote display and iPhone controller.
- **GitHub / folders** — one-click access to the two projects.
- **Health panel** — checks project paths, Node/Git availability, and the NexQ LAN port.

## One-click start

Double-click `NexQ-Suite.bat`.

The launcher tries these locations automatically:

- `%USERPROFILE%\NexQ-fixed`
- `%USERPROFILE%\Desktop\NexQ-fixed`
- `%USERPROFILE%\Desktop\3v0l-interview`

For different locations, set environment variables before launching:

```bat
set NEXQ_HOME=D:\Projects\NexQ-fixed
set EV0L_HOME=D:\Projects\3v0l-interview
launcher\NexQ-Suite.bat
```

## Design intent

The launcher is deliberately dependency-free: it uses built-in Windows PowerShell/WPF, so the cockpit itself does not require npm packages.
