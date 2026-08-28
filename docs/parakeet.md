# Tester Parakeet / Nemotron avec Mattermost Calls

Image dédiée CPU : post-call **Parakeet TDT 0.6B v3**, live captions **Nemotron 3.5 ASR streaming 0.6B**, via NeMo-Speech.cpp (GGUF Q8). Whisper reste dans l’image.

Le transcriber ne expose pas de port. C’est **calls-offloader** (port **4545**) que Mattermost appelle. L’offloader lance ensuite le conteneur `calls-transcriber:master`.

Prévoir ~10 Go de disque (deux GGUF ~1,45 Go + Whisper.cpp) et plusieurs Go de RAM à l’inférence.

## 1. Construire l’image transcriber

Depuis `calls-transcriber` :

```bash
make docker-build-parakeet
```

Tags locaux : `calls-transcriber:master` (attendu par l’offloader en `DEV_MODE`) et `calls-transcriber:parakeet`.

NeMo-Speech.cpp n’est **pas** compilé : on prend l’archive CPU officielle [v0.1.0](https://github.com/NVIDIA/NeMo-Speech.cpp/releases/tag/v0.1.0) (`include/` + `libnemo_speech_asr_c.so`, ~4 Mo). Whisper.cpp se compile dans l’image (cache BuildKit `/cache/deps` + ccache : pas de re-wget/re-cmake si les artefacts sont là). Les deux GGUF (~1,45 Go) sont téléchargés **une fois** dans `.cache/parakeet-models` (gitignored) puis copiés ; les rebuilds suivants réutilisent ce cache.

Après un rebuild, pas besoin de relancer Mattermost ni l’offloader. `DEV_MODE` prend `calls-transcriber:master` au **prochain** job d’enregistrement.

## 2. Lancer l’offloader (port 4545)

L’offloader a besoin du socket Docker pour créer les jobs.

### Option A — binaire sur l’hôte (simple)

```bash
cd /home/thomas/git/github/calls-offloader
make go-run
```

Avec :

```bash
export API_SECURITY_ALLOWSELFREGISTRATION=true
export DEV_MODE=true
export DOCKER_NETWORK=host
```

`DEV_MODE=true` force le runner `calls-transcriber:master` (image locale, pas de pull Docker Hub).

Vérifier :

```bash
curl -s http://127.0.0.1:4545/version
```

### Option B — compose (offloader dans Docker, port mappé)

Depuis `calls-transcriber` :

```bash
docker compose -f build/parakeet/docker-compose.yml up --build -d
curl -s http://127.0.0.1:4545/version
```

Le socket Docker est monté. `user: "0:0"` est volontaire : le binaire distroless tourne sinon en user `calls` sans accès au socket.

## 3. Pointer Mattermost vers l’offloader

System Console → Plugins → Calls → **Job service URL** :

- Mattermost sur la même machine : `http://127.0.0.1:4545`
- Mattermost dans Docker : `http://host.docker.internal:4545` (Linux : ajouter `host.docker.internal:host-gateway` sur le conteneur Mattermost, ou utiliser l’IP de l’hôte)

Activer recordings + transcriptions (+ live captions si besoin).

Sans patch du plugin Calls, forcer Parakeet par override d’env **sur le serveur Mattermost** (déjà relayé au job) :

```bash
# API post-call + live (lu par le transcriber)
export MM_CALLS_TRANSCRIBER_TRANSCRIBE_API=parakeet

# Live captions : défaut produit = en → en-US. Instance FR :
export MM_CALLS_LIVE_CAPTIONS_LANGUAGE=fr
# ou locale explicite :
# export MM_CALLS_LIVE_CAPTIONS_LANGUAGE=fr-FR

# Post-call : vide = auto-detect. Forcer FR seulement si besoin :
# export MM_CALLS_TRANSCRIBER_ASR_LANGUAGE=fr-FR
```

Redémarrer Mattermost après ces variables.

`fr` est mappé vers `fr-FR`. Une locale avec un tiret (`pt-BR`, `en-GB`) est passée telle quelle. `auto` laisse le modèle détecter. Valeur inconnue → auto-detect, jamais de crash.

## 4. Site URL interne

Si Mattermost n’est pas joignable depuis les jobs via l’URL publique :

```bash
export MM_CALLS_TRANSCRIBER_SITE_URL=http://127.0.0.1:8065
```

Avec `DOCKER_NETWORK=host`, `127.0.0.1` est l’hôte.

## 5. Vérifier un job

Après un appel enregistré :

```bash
docker ps --filter label=app=mattermost-calls-offloader
docker logs <container_calls-transcriber>
```

Logs attendus : `nemotron live captions recognizer ready` si les live captions sont on ; puis transcription Parakeet au `handleClose`.

## Licences (image)

Voir `build/licenses/NOTICE` : Parakeet CC-BY-4.0, Nemotron OpenMDW-1.1, NeMo-Speech.cpp Apache-2.0.
