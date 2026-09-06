# PoE1 Path of Building MCP — zelf hosten met Docker/Portainer

Dit bouwt exact het prototype dat in de sessie is geverifieerd: een headless, echte
Path of Building-rekenengine (PoE1, PathOfBuildingCommunity, dev-branch) aangestuurd
via [ianderse/pob-mcp](https://github.com/ianderse/pob-mcp), in een container.

## Belangrijk om te weten vóór je dit deployt

**Dit is geen netwerkservice.** De MCP-server praat uitsluitend via *stdio*
(standaard in/uit) — er is geen HTTP- of SSE-poort. Dat betekent:

- Je moet dit **niet** als "always-on achtergrondservice" draaien met
  `docker compose up -d`. Er zit niemand aan de stdin/stdout, dus zo'n
  container doet niets nuttigs en zou meteen stoppen of nutteloos idle staan.
- Het juiste gebruik: de MCP-client (bijvoorbeeld Claude Desktop, of een
  eigen agent) **start deze container zelf, per sessie**, en praat via de
  aangekoppelde stdin/stdout. Portainer/Docker bouwt en bewaart hier dus het
  *image* klaar voor gebruik — het start het niet zelf 24/7.

## 1. Image bouwen (via Portainer)

Belangrijke valkuil: Portainer's **Upload**-tab bij "Add stack" bouwt de image
via BuildKit met alléén de bestanden die je daar zelf selecteert als bouwcontext
— een los aangeleverd `.zip`-bestand met alles in een submap erin (zoals de
eerste versie die hier gedeeld werd) laat de `Dockerfile` op de verkeerde plek
belanden, met precies de foutmelding "no such file or directory" tot gevolg.

Zo werkt het wel betrouwbaar:

1. Pak de zip lokaal uit — dit keer staan `Dockerfile`, `entrypoint.sh`,
   `docker-compose.yml`, `.dockerignore` en `README.md` los naast elkaar
   (geen submap meer).
2. Portainer → **Stacks → Add stack → Upload**.
3. Selecteer bij "Upload" **alle bestanden tegelijk** (Dockerfile,
   entrypoint.sh, docker-compose.yml, .dockerignore) — niet de zip zelf, en
   niet alleen het compose-bestand. Portainer moet de Dockerfile letterlijk
   als los bestand naast de compose-file krijgen om hem in de bouwcontext op
   te nemen.
4. Als jouw Portainer-versie bij "Upload" maar één bestand toelaat (sommige
   versies doen dat): gebruik dan in plaats daarvan **Repository** (een
   git-repo met deze bestanden erin) — dat is de meest betrouwbare manier om
   een Dockerfile + compose samen te deployen, ongeacht Portainer-versie.

Portainer bouwt dan het image `pob-mcp:poe1`. De eerste build duurt een paar
minuten (LuaJIT compileren, PathOfBuilding + pob-mcp clonen, npm install).

Vanaf de command line (bijvoorbeeld via SSH op je Synology/NAS) kan dat ook
gewoon met, vanuit de map met deze bestanden:

```bash
docker compose build
```

Dat laatste omzeilt meteen alle Portainer-upload-eigenaardigheden, en is het
makkelijkst te debuggen als er iets misgaat.

## 2. De container daadwerkelijk gebruiken

### Als je MCP-client op dezelfde machine draait als Docker

Wijs de client naar dit commando (bijvoorbeeld in Claude Desktop's
`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "pob-poe1": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "pob-builds:/data/builds",
        "pob-mcp:poe1"
      ]
    }
  }
}
```

(`docker compose run --rm pob-mcp` werkt ook, als je vanuit deze map draait.)

### Als je MCP-client op een ándere machine draait dan de Docker/Portainer-host

Stdio gaat niet vanzelf over het netwerk. De simpelste, werkende oplossing is
het via SSH te tunnelen — SSH geeft transparant stdin/stdout door:

```json
{
  "mcpServers": {
    "pob-poe1": {
      "command": "ssh",
      "args": [
        "gebruiker@docker-host",
        "docker run -i --rm -v pob-builds:/data/builds pob-mcp:poe1"
      ]
    }
  }
}
```

Dit vereist dat `gebruiker@docker-host` zonder wachtwoordprompt kan inloggen
(SSH-key) vanaf de machine waar de MCP-client draait.

## 3. Builds bewaren

`POB_DIRECTORY=/data/builds` staat in het image, gekoppeld aan het named
volume `pob-builds`. Builds die je via de MCP-tools opslaat, overleven dus
het verwijderen/herstarten van een container.

## 4. Bijwerken voor een nieuwe league

PoE1 krijgt ongeveer elke drie maanden een nieuwe league met nieuwe data. Twee opties:

- **Automatisch bij opstarten** (standaard aan, `POB_AUTO_UPDATE=true`): elke
  keer dat de container start, doet hij `git pull` op de PathOfBuilding-checkout
  vóór de MCP-server start. Handig, maar betekent dat je niet 100% reproduceerbaar
  vastzet welke versie draait.
- **Handmatig vastzetten**: zet `POB_AUTO_UPDATE=false` en bouw het image opnieuw
  met een vaste `POB_REF` (tag of commit-hash) in `docker-compose.yml`, zodat je
  precies weet welke leagueversie je draait.

## Bekende beperking uit het prototype

De tool `generate_weighted_trade_query` (trade-site zoekfilters genereren) gaf
tijdens het testen een fout (`Extra argument passed to new() during creation of
class TradeQueryGenerator`) — een compatibiliteitsbugje tussen pob-mcp's eigen
Lua-adapter en de huidige PathOfBuilding dev-branch. De kernfunctionaliteit
(exacte stat-/DPS-/EHP-berekening, boom-editing, items, gems) werkt hier niet
door geraakt. Dit kan opnieuw ontstaan bij `POB_AUTO_UPDATE=true` als PoB verder
verandert — zie de bevindingen in het POE-project (`poe1-pob-mcp-prototype-resultaten.md`).

## Wat er in dit image zit (en waarom)

- **LuaJIT**, gebouwd vanaf commit `2460b3ff93a1c955de3d62cfc825de7d68dc272e` van
  het officiële LuaJIT-project — dit is exact het commit dat
  PathOfBuildingCommunity's eigen `Dockerfile` gebruikt. Nodig omdat gepakte
  distributieversies (bijv. Ubuntu's apt-package) een syntax die PoB's code
  gebruikt (`count += 1`) nog niet ondersteunen.
- **lua-utf8**, een native module die PoB's Windows-runtime als `.dll` meelevert
  maar waarvan geen Linux-`.so` in de repo zit — hier gecompileerd vanaf
  [starwing/luautf8](https://github.com/starwing/luautf8).
- **PathOfBuildingCommunity/PathOfBuilding** (dev-branch, MIT-gelicenseerd) — de
  officiële PoE1-databron én rekenengine. Geen spel-clientbestanden nodig.
- **ianderse/pob-mcp** — de MCP-server die de bovenstaande engine headless aanstuurt.
