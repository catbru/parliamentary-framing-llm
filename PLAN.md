PLA MESTRE: NLP Parlament d'Andalusia
=====================================

**Objectiu:** Desenvolupar un pipeline integral basat en R per extraure, estructurar i analitzar les intervencions dels diputats del Parlament d'Andalusia. L'objectiu final és aplicar tècniques de NLP (via LLMs) per estudiar l'enquadrament polític (framing) i el posicionament (stance) en debats concrets sobre Catalunya, facilitant la recerca en ciència política computacional.

1\. FONT DE DADES I ENDPOINTS TÈCNICS
-------------------------------------

S'ha descartat l'anàlisi de PDFs. La font principal de dades és la Videoteca del Parlament, que oculta una API JSON amb transcripcions segmentades (Speech-to-Text). *Avaluació de dades:* Les transcripcions (STT) només estan disponibles per a les legislatures 12 (actual), 11 i 10.

### 1.1. Obtenció del Catàleg (Web Scraping)

-   **URL Base:** `https://videoteca.parlamentodeandalucia.es/search`

-   **Filtres objectiu (Plens):** `?view_type=list&legs_id=3377&gbody_id=3378` (On `gbody_id=3378` assegura que només s'extreuen Sessions de Ple).

-   **Acció:** Fer scraping d'aquesta URL per extreure els enllaços dels vídeos (`/watch?id=...`).

-   **Output (JSON):** Es desarà a `01_dades_crues/cataleg/cataleg_videos.json`. Aquest fitxer contindrà un array d'objectes bàsics amb l'ID en Base64 de la URL pública, el títol de la sessió i la data i tota la metadata sobrre la sessió que sigui rellevant i estigui disponible al propi html.

### 1.2. La "Pedra de Rosetta" (Mapeig URL -> API)

La URL pública utilitza un ID en Base64. L'API JSON requereix un `ID_MASTER` intern.

-   **Procés:** Fer una petició GET a la URL del vídeo (ex: `/watch?id=OGI2M2...`).

-   **Extracció:** Buscar dins del codi font HTML el bloc `<!-- JSPLAYLIST -->`.

-   **Regex clau:** Capturar el valor numèric de `subject_id` (ex: `subject_id=27084`). Aquest és el nostre `ID_MASTER`.

-   **Output (JSON):** S'actualitzarà el catàleg inicial generant un nou fitxer `01_dades_crues/cataleg/cataleg_master.json`. Aquest fitxer afegirà a cada registre de la sessió el camp `ID_MASTER` definitiu, que servirà com a clau primària per a tots els passos posteriors.

### 1.3. L'API d'Estructura i Transcripció (Procés en 2 passos)

Per evitar saturar el servidor o rebre errors de *timeout*, l'extracció es fa en dos temps:

-   **PAS 1 (Esquelet de la sessió):**

    -   `GET https://videoteca.parlamentodeandalucia.es/api/masters/{ID_MASTER}/timeline.json?end=999999999999&start=0`

    -   Objectiu: Obtenir l'arbre de la sessió (punts del dia, oradors) i els temps (`start` i `end`) de cada intervenció.

    -   **Output (JSON):** Es desarà un fitxer per sessió a `01_dades_crues/sessions_esquelet/{ID_MASTER}_esquelet.json`. Contindrà el JSON original de l'API, mostrant l'estructura jeràrquica de la sessió (sense les transcripcions textuals).

-   **PAS 2 (Transcripció - STT):**

    -   Iterar sobre cada intervenció identificada al Pas 1.

    -   `GET https://videoteca.parlamentodeandalucia.es/api/masters/{ID_MASTER}/timeline.json?end={FI_INTERVENCIO}&start={INICI_INTERVENCIO}&stt=records`

    -   Objectiu: Obtenir l'array `stt` amb el text exacte per a aquella franja.

    -   **Output (JSON):** Es desarà un fitxer per *cada intervenció individual* a `01_dades_crues/intervencions_stt/{ID_MASTER}_{ID_ORDRE}_{NOM_DIPUTAT}.json`. L'interior d'aquest JSON contindrà exclusivament el text json original d'aquell diputat (marques de temps, etc).

### 1.4. Metadades de Diputats

-   **Directori:** `https://videoteca.parlamentodeandalucia.es/people`

-   **Acció:** Extreure un diccionari que relacioni "Nom Normalitzat" amb el seu "Partit Polític" i "Legislatura" i altra informació bàsica del diputat per poder creuar-ho amb les dades de l'API.

-   **Output (JSON):** Es desarà a `01_dades_crues/diputats/diputats.json`. Serà un diccionari (o array d'objectes) que actuarà com a taula relacional.

2\. ARQUITECTURA DEL SISTEMA (L'Ecosistema R)
---------------------------------------------

S'ha optat per una arquitectura minimalista, sense bases de dades complexes, ideal per a un equip de politòlegs avesat a `R` i el `Tidyverse`.

### 2.1. Estructura de Carpetes Plana i Resilient

Aquesta estructura compartimentada garanteix traçabilitat i evita problemes d'escriptura creuada si el procés s'interromp.

```
projecte_parlament/
├── .env                        # Variables d'entorn (API Keys, etc.)
├── 00_scripts_R/
│   ├── 1_scraper_cataleg.R     # Scraping de `/search` i resolució del `ID_MASTER` (Pedra de Rosetta)
│   ├── 2_scraping_diputats.R   # Creació de la taula relacional de diputats i partits
│   ├── 3_api_sessions.R        # Baixada d'esquelets de sessions i intervencions amb STT
│   ├── 4_llm_framing.R         # Filtre per keywords i crides a l'API del LLM (Codebook)
│   └── 5_analisi_i_plots.qmd   # Anàlisi Tidyverse (Dplyr, Ggplot) de resultats consolidats
├── 01_dades_crues/
│   ├── cataleg/
│   │   ├── cataleg_videos.json        # Resultat directe del cercador
│   │   └── cataleg_master.json        # Resultat amb el mapeig a `ID_MASTER` completat
│   ├── diputats/
│   │   └── diputats.json              # Fitxer diccionari de diputats
│   ├── sessions_esquelet/
│   │   ├── 26975_esquelet.json        # Estructura del Ple de la sessió 26975 (sense text)
│   │   └── ...
│   └── intervencions_stt/
│       ├── 26975_001_aguirre.json     # Transcripció STT completa de la primera intervenció
│       ├── 26975_002_gomez.json
│       └── ...
└── 02_dades_processades/
    ├── dataset_consolidat/
    │   └── corpus_complet.parquet     # (Opcional) Dades crues unificades per a una càrrega ràpida en R
    └── llm_frames/
        ├── 26975_001_aguirre.json     # JSON de sortida de l'LLM responent als ítems del Codebook
        └── ...

```

### 2.2. Principis de Desenvolupament (Directrius per a Scripts)

1.  **Join per Nomenclatura:** Els noms dels fitxers han de contenir les claus primàries (Sessió, Ordre d'intervenció) per facilitar la reconstrucció del dataset mitjançant funcions de la família `join` de `dplyr`.

2.  **Tolerància a errors i represes:** Tots els bucles d'R que facin crides de xarxa (Scripts 1, 3 i 4) **han de comprovar si el fitxer de destinació ja existeix** (`file.exists()`). En cas afirmatiu, saltar a la següent iteració. Ús obligatori de `tryCatch()` per no aturar el pipeline davant d'un error 404 o 500 aïllat.

3.  **Consolidació Final:** Al final dels processos, scripts R empaquetaran els milers de JSONs en objectes eficients (`.parquet` o `.rds`) via `jsonlite` o `tidyr::hoist()` per a una càrrega ràpida en anàlisi, evitant el lent procés de llegir multitud de fitxers des del disc al `.qmd`.

4.  **Paquets recomanats:** `rvest` (HTML), `httr2` (APIs), `jsonlite` (Dades), `stringr` (Regex), `dplyr`/`purrr` (Manipulació).

3\. PROCESSAMENT NLP I METODOLOGIA (Codebook LLMs)
--------------------------------------------------

Per avaluar l'evolució discursiva (hipòtesi: efecte contagi o polarització), s'utilitzarà un sistema de "Codebook LLM" (Halterman & Keith, 2024).

### 3.1. Filtre Inicial

Identificació (via Regex R) d'intervencions que continguin variants de la paraula objectiu (ex: `(?i)catalu[ñn]a|catalanes|generalitat|independentistas`).

### 3.2. Classificació amb LLM (Prompting Estructurat i Llibre de Codis)

Els textos filtrats s'enviaran a un LLM (via API, ex. OpenAI o Anthropic). El *system prompt* base instruirà el model de la següent manera: *"La teva tasca com a assistent d'investigació computacional és analitzar extractes d'intervencions de diputats del Parlament d'Andalusia que contenen mencions a Catalunya. Per a cada extracte, has de determinar el Sentiment i l'Enquadrament Principal (Frame) seguint ESTRICTAMENT les definicions i regles de tancament següents."*

A continuació es detalla l'estructura completa que conforma les instruccions del model:

#### A. DIMENSIÓ 1: Sentiment / To (Variable: `sentiment_cat`)

S'avaluarà l'actitud explícita cap a les institucions catalanes, el moviment polític català o la societat catalana esmentada en el text:

-   **`Hostil_Negatiu`**: Utilitza llenguatge pejoratiu, agressiu o d'alarma ("golpistas", "chantaje", "ruptura", "privilegios").

-   **`Neutral_Institucional`**: Fa referència a fets objectius, dades estadístiques comparades o procediments legals sense càrrega valorativa explícita.

-   **`Empàtic_Positiu`**: Mostra solidaritat, posa Catalunya com a exemple d'una bona política pública o fa crides a l'entesa i el diàleg plurinacional.

#### B. DIMENSIÓ 2: Enquadrament Principal (Variable: `primary_frame`)

Identifica la lent o perspectiva principal a través de la qual s'introdueix el tema de Catalunya en el debat andalús. Si n'hi ha més d'un, es tria el que ocupi més espai argumental.

1.  **Greuge Comparatiu / Finançament (`Grievance_Economics`)**

    -   *Definició:* L'orador esmenta Catalunya per argumentar que Andalusia està infrafinançada, ignorada o perjudicada en favor de concessions econòmiques o competencials a Catalunya.

    -   *Regla d'Exclusió:* NO utilitzis aquesta etiqueta si es parla d'economia catalana de forma aïllada sense comparar-la amb Andalusia o el pressupost de l'Estat.

2.  **Amenaça Constitucional i Ordre (`Constitutional_Threat`)**

    -   *Definició:* L'orador esmenta Catalunya com una amenaça per a la unitat d'Espanya, l'Estat de Dret o la igualtat dels espanyols. El focus no és els diners, sinó la legalitat, la nació i la moralitat de l'independentisme.

    -   *Regla d'Exclusió:* NO utilitzis aquesta etiqueta si la crítica se centra només en la gestió econòmica de la Generalitat sense mencionar la ruptura d'Espanya o el procés independentista.

3.  **Instrument Nacional / Atac al Rival (`Electoral_Weaponization`)**

    -   *Definició:* L'orador utilitza els pactes amb partits catalans per atacar el govern espanyol o el rival polític regional (ex: el PP atacant el PSOE andalús per les decisions del PSOE nacional).

    -   *Regla d'Exclusió:* NO utilitzis aquesta etiqueta si la crítica va dirigida EXCLUSIVAMENT al govern català. Ha d'incloure un atac directe a un partit d'àmbit nacional (PSOE, PP, Sumar, etc.).

4.  **Model o Referent Positiu (`Positive_Reference`)**

    -   *Definició:* L'orador esmenta Catalunya com un exemple a seguir, una referència d'una bona pràctica, una política pública exitosa o un model d'èxit econòmic/social que Andalusia hauria d'imitar.

    -   *Regla d'Exclusió:* NO utilitzis aquesta etiqueta si la menció positiva es fa únicament per justificar una aliança política partidista sense referenciar un model de gestió concret.

5.  **Altres / Moció de Tràmit (`Other`)**

    -   *Definició:* Mencions a Catalunya que no encaixen en els marcs anteriors (resultats esportius, referències geogràfiques menors).

#### C. EXEMPLES DE REFERÈNCIA (Few-Shot Prompts)

El prompt inclourà exemples per ensenyar a raonar a l'LLM:

-   **Exemple A:**

    -   *Text:* "Señorías del PSOE, ustedes vienen aquí a darnos lecciones de sanidad pública, pero luego callan cobardemente mientras su jefe en Moncloa riega con miles de millones a los separatistas catalanes para mantenerse en el sillón, robándole el dinero que le corresponde a los hospitales de Sevilla o Jaén."

    -   *Sortida esperada:* `sentiment_cat: "Hostil_Negatiu"`, `primary_frame: "Electoral_Weaponization"`. *Raonament:* Ataca l'adversari (PSOE) per accions del seu líder amb relació al finançament de Catalunya, establint una condició d'instrumentalització molt explícita.

-   **Exemple B:**

    -   *Text:* "Tenemos que fijarnos en cómo otras comunidades están gestionando la FP Dual. En Cataluña, el tejido industrial lleva años colaborando con los centros educativos, con una tasa de inserción que aquí deberíamos aspirar a replicar."

    -   *Sortida esperada:* `sentiment_cat: "Empàtic_Positiu"`, `primary_frame: "Positive_Reference"`. *Raonament:* Catalunya es menciona exclusivament com un referent en política educativa a emular, sense to pejoratiu ni conflicte polític.

#### D. FORMAT DE SORTIDA EXIGIT (JSON SCHEMA)

Per forçar que l'LLM retorni dades estables, l'script R enviarà a l'API aquest objecte `JSON Schema` (e.g. mitjançant els paràmetres `response_format` d'OpenAI o `responseSchema` de Gemini). Tots els fitxers resultants a `02_dades_processades/llm_frames/` compliran rigorosament aquesta estructura:

```
{
  "type": "object",
  "properties": {
    "chain_of_thought": {
      "type": "string",
      "description": "Raonament detallat basat explícitament en les regles d'exclusió del codebook (màxim 3-4 frases)."
    },
    "sentiment_cat": {
      "type": "string",
      "enum": [
        "Hostil_Negatiu",
        "Neutral_Institucional",
        "Empàtic_Positiu"
      ],
      "description": "Categorització del to explícit utilitzat cap a les institucions o societat catalana."
    },
    "primary_frame": {
      "type": "string",
      "enum": [
        "Grievance_Economics",
        "Constitutional_Threat",
        "Electoral_Weaponization",
        "Positive_Reference",
        "Other"
      ],
      "description": "El marc discursiu principal utilitzat en el text."
    },
    "confidence_score": {
      "type": "number",
      "description": "Nivell de certesa sobre la classificació, entre 0.0 i 1.0."
    }
  },
  "required": [
    "chain_of_thought",
    "sentiment_cat",
    "primary_frame",
    "confidence_score"
  ],
  "additionalProperties": false
}

```

### 3.3. Control Endogen (Mètode Polític)

Durant l'anàlisi (Script 5), serà obligatori creuar les dades de NLP amb la variable `Estatus del Partit` (Govern / Oposició), ja que els canvis de discurs entre 2017 i 2019 al Parlament andalús poden deure's al canvi de rol institucional (PSOE passa a l'oposició, PP al govern) i no exclusivament a l'entrada de l'extrema dreta.