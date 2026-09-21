# MiSTer-Raster

---

## Purpose

MiSTer-Phosphor is a mp3,ogg,wav, and flac player for the MiSTer FPGA.

---

## Standards

- Use ISO-8601 timestamps with the local UTC offset. Timezone is America/Phoenix.

- When needing to look up reference material, use core-reference.md as an authoritative source when attempting to lookup anything that could be considered a standard, conformance, specification, etc. as opposed to looking it up online.

- If you are not able to find the information you need by consulting core-reference.md, look up the standard online you trust and make an educated determination if you would like to add it to your core-reference.md document following existing syntax and formatting for future reference.

- If a more recent or otherwise more valid source is discovered during your online research and it is not documented in core-reference.md, you are to notify the user.

- Diagnostic implementation limits must not be described as standard limits.

- Respect all standard licensing and attribution conventions.

---

## AI Agent Recovery Policy

Read this core.md file first. Treat core.md is the primary project-level source of directives subject to active higher-priority and current user instructions. Read core-log.md second as historical engineering/build/transcript evidence and the primary project-level source of context, The online GitHub repository is the backup source for archival information. Treat core.md as RESTRICTED, authoritative project core memory. Do not edit it automatically for any reason. Only edit core.md if the user explicitly asks for it.

---

## Build Environment

- The GitHub repository for this project is: https://github.com/aquasock/MiSTer-Phosphor.git

- The user's local GitHub repository must always stay up to date with the online repository.

- The tar.gz archives stored in the "archived_logs" folder are not to be referenced unless approval from the user is given first.

- Do not create branches if possible. Always work off of master unless otherwise instructed.

- The build enviroment consists of Quartus Prime v17.0.2 Lite, and a QMTech MiSTer.

---

## Agent Behavior

- Keep project conversation limited to project enviroment.

- No need to be polite when speaking, Communicate as you would in a standard engineering enviroment.

- Assume all user commands are run from the local GitHub root.

- Split changes further only when risk, standards uncertainty, diagnostic isolation, or new evidence makes a smaller boundary materially safer.

- If new findings would materially change the approved plan, stop and obtain user approval for the revised plan before continuing.

- Generated binary regression artifacts and diagnostic tools the user is intended to run should normally be produced by deterministic scripts committed under "tools" and generated locally by the user or agent.

- Treat core-log.md as a ring buffer. Only 100 entries are ever allowed. If the log is full, tar.gz it with the current date and time into the "archived_logs" folder, clear the current core-log.md, and add an handoff entry in the empty core-log.md.

- The folder labeled "ai" on the GitHub repository’s root is your core project folder and contains your core directives, (core.md) running project memory, (core-log.md), reference library (core-reference.md), and syntax guidelines (core-syntax.md).

- A core-syntax.md audit must be done any time changes are made to any of the files in your core project folder except core-syntax.md. 

- Use the commit message "(<current_short_commit>) core-log.md update" for all updates you make to core-log.md. 

- Use the commit message "(<current_short_commit>) core.md update" for all updates you make to core.md. 

- Use the commit message "(<current_short_commit>) core-reference.md update" for all updates you make to core-reference.md. 

- Use the commit message "(<current_short_commit>) core-syntax.md update" for all updates you make to core-syntax.md. 

- (<current_short_commit>) means the abbreviated SHA of the development/source commit being documented. Subsequent metadata-only .ai commits continue to reference that source commit for the same development cycle.

- You have full read and write access to the users local GitHub repository and may run build tools in the user's local enviroment.

- When possible, provide the user with a progress bar based on historical build logs when compiling or running timing.

- The test MiSTer is to be accessed through standard FPT using the default MiSTer username and password.

- Use the helper scripts found in "tools" to perform basic build and diagnostic functions. 

---

## Target Environment

- Treat the user's current MiSTer hardware configuration as the standard development target unless the user says otherwise.

- The user's standard target is as follows:

```text
DE10-Nano-compatible Cyclone V SoC MiSTer system

Linux:
Kernel: Linux MiSTer 5.15.1-MiSTer
Build:  Wed Apr 2 20:01:54 CST 2025

HPS CPU:
ARM Cortex-A9
2 cores
ARMv7 little-endian
CPU range: 400 MHz - 1.2 GHz

HPS RAM visible to Linux:
MemTotal: 504096 kB
Approx. 492 MiB Linux-visible

HPS <-> FPGA Bridges:
Lightweight HPS-to-FPGA: present
HPS-to-FPGA:             present
FPGA-to-HPS:             present

Ethernet:
Controller: Cyclone-V HPS DWMAC1000
PHY: Micrel/Microchip KSZ9031
Link: 1 Gbit/s Full Duplex

I2C:
m41t81  @ 0x68   - operational / supplies rtc

Power:
Idle Current: ~1.1A
```

---

## Standard Workflow:

1. Review the available build and test logs, identify the observed failures or required work, and prepare a proposed plan of action to the user. 

2. If the plan is approved by the user, Update core-log.md with your proposal and commit it to the online repository.

3. Make changes to the local GitHub source code directly that are aligned with your proposed changes in core-log.md.

4. Commit the changes to the online repository with a commit message that follows previous agents commit message conventions. This will become the next build's official commit hash.

5. You will then build the project yourself and inform the user the build is ready for testing.

6. I will inform you when my test results are ready in the local project's "current_results" folder.

7. Update core-log.md with the test results and commit it to the online repository.

8. Repeat.

---

## Versioning

- This project uses Semantic Versioning for GitHub releases.

- The first release is version 0.1.0.

- Git tags and GitHub releases use a leading `v`, for example `v0.1.0`, while the human-readable project version is `0.1.0`.

- While the project remains pre-1.0, increment MINOR for each new hardware-proven development milestone that adds meaningful capability (0.1.0 -> 0.2.0 -> 0.3.0).

- Increment PATCH for fixes or release corrections that do not constitute a new milestone (0.1.0 -> 0.1.1).

- Reserve 1.0.0 for a future user-ready compatibility baseline explicitly approved by the user.

---

## Releasing

- Keep `CHANGELOG.md` in Keep-a-Changelog style: maintain an `Unreleased` section during development; at release, move accepted milestone changes under a `## [X.Y.Z] - YYYY-MM-DD` heading and start a fresh `Unreleased` section.

- Release notes should summarize the milestone, supported/known limitations, hardware validation performed, and any important timing/resource information.

- The agent is responsible for source/version metadata, changelog/release notes during release.

- Mark pre-1.0 releases as pre-release on GitHub unless the user explicitly decides otherwise.

- MiSTer binary naming follows the MiSTer core convention rather than Semantic Versioning.

1. Perform a full regression test suite with a clean/from-scratch Quartus build and verify the results.

2. Update the README.md and CHANGELOG.md on the project's GitHub repository and commit the change.

3. Have the user create the annotated/version tag and GitHub Release from that exact commit so source, release notes, and binary package are reproducible.

4. Push the release onto GitHub.

---
