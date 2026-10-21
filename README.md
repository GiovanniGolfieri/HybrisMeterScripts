# HybrisMeter — Platform scripts

Root folder of the **HybrisMeter** platform: the shared scripts and documents that do not belong to a single component.
Each component has its own repository, cloned inside this folder (they are ignored here).

| Folder          | Repository                                             | Content                                   |
|-----------------|--------------------------------------------------------|-------------------------------------------|
| `DB/`           | `GiovanniGolfieri/HybrisMeterDB`                       | PostgreSQL schema and stored functions    |
| `BE/`           | `GiovanniGolfieri/HybrisMeterBE`                       | FastAPI backend and Node.js services      |
| `FE/`           | `GiovanniGolfieri/GiovanniGolfieri-HybrisMeterFE`      | Next.js web platform                      |
| `INSTALLERAPP/` | `GiovanniGolfieri/INSTALLERAPP`                        | Android app of the installer              |
| `USERAPP/`      | `GiovanniGolfieri/USERAPP`                             | Android app of the end user               |

## Content of this repository

- `CLAUDE.md` — entry point of the project documentation (each component has its own)
- `INSTALL.md` — installation of a development PC
- `GRANT.md`, `PARAMETRI-RIPARTI.md` — permission model, allocation parameters
- `version.sh` + `.githooks/` — single platform version and the shared pre-commit hook of the five repositories
- `run-tests.sh` — the whole test battery (disposable database, never a real one)
- `start-be.sh`, `start-fe.sh` — local start of backend and frontend

## Setting up a new PC

```bash
git clone git@github.com:GiovanniGolfieri/HybrisMeterScripts.git HybrisMeter
cd HybrisMeter
git clone git@github.com:GiovanniGolfieri/HybrisMeterDB.git DB
git clone git@github.com:GiovanniGolfieri/HybrisMeterBE.git BE
git clone git@github.com:GiovanniGolfieri/GiovanniGolfieri-HybrisMeterFE.git FE
git clone git@github.com:GiovanniGolfieri/INSTALLERAPP.git INSTALLERAPP
git clone git@github.com:GiovanniGolfieri/USERAPP.git USERAPP
./version.sh install      # enables the shared hook in the five repositories
```

Then follow [INSTALL.md](INSTALL.md).
