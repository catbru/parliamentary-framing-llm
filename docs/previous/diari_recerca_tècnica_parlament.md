Diari de recerca tècnica
NLP Parlament d'Andalusia
===========================================

Aquest document recull les troballes, proves i decisions preses durant la fase d'exploració i disseny del sistema d'extracció de dades del Parlament d'Andalusia.

Entrada 1: Descobriment de l'API de la Videoteca
------------------------------------------------

**Data:** 22 d'abril de 2026

S'ha descobert que la plataforma de vídeos del Parlament d'Andalusia ofereix les intervencions segmentades, transcrites i, el més important, accessibles a través d'una API interna que retorna dades estructurades en format JSON.

### 1\. URLs i Endpoints

-   **URL de visualització web (exemple):** `https://videoteca.parlamentodeandalucia.es/watch?id=MzhiODQxYTQtOTU2Yi00YmQyLTk2MTUtMTVlMjEyMTZlZWU1`

-   **Endpoint de l'API (Timeline):** `https://videoteca.parlamentodeandalucia.es/api/masters/{ID_MASTER}/timeline.json`

### 2\. Modes d'ús de l'API

#### A. Extracció de l'estructura de la sessió (Sense text)

Modificant els paràmetres de temps (`start=0` i un `end` molt alt), l'API retorna l'estructura completa de la sessió: punts de l'ordre del dia, qui parla, i els temps d'inici i final de cada intervenció.

**Crida:** `?end=99999999999999999999999999&start=0` **Estructura JSON (resum):**

```
{
  "data": {
    "record": {
      "timeline": {
        "id": 26975,
        "sections": [
          {
            "name": "[START] / Punt del dia",
            "start": "0.000",
            "end": "189.793",
            "sections": [
              {
                "name": "Aguirre Muñoz, Jesús", // Nom del Diputat
                "start": "22.390",
                "end": "189.793",
                "duration": "167.403"
              }
            ]
          }
        ]
      }
    }
  }
}

```

#### B. Extracció del text de les intervencions (STT)

Afegint el paràmetre `stt=records` i ajustant l'inici i final, l'API retorna la mateixa estructura però incloent un array `stt` amb les paraules/frases exactes i els seus timestamps dins de cada intervenció.

**Crida:** `?end=808&start=408&stt=records` **Estructura JSON (resum):**

```
{
  // ... (mateixa jerarquia d'abans)
  "sections": [
    {
      "name": "Gómez Jurado, José Manuel",
      "stt": [
        {
          "start": "407.960",
          "end": "408.260",
          "text": "bien"
        }
      ]
    }
  ]
}

```

### 3\. Implicacions per al Projecte

1.  **S'evita el PDF Parsing:** No caldrà lidiar amb el format complex dels *Diarios de Sesiones* en PDF o HTML.

2.  **Dades enriquides:** Tenim l'ordre del dia associat a la intervenció i el nom del diputat ja normalitzat.

3.  **Pipeline d'extracció:** El procés consistirà en fer dues crides: la primera per mapejar l'estructura completa de la sessió (qui parla i quan), i successives crides per recollir el text (STT) de les franges temporals on ens interessi o de cop.

Entrada 2: Obtenció de Metadades dels Diputats
----------------------------------------------

**Data:** 22 d'abril de 2026

Per donar context a la recerca sociopolítica, no només necessitem el text de la intervenció, sinó informació sobre l'orador (partit polític, legislatura en la qual actua, etc.). S'ha localitzat la secció de la videoteca on resideix aquesta informació.

### 1\. URLs Identificades

-   **Llistat de Diputats i Filtres:** La url principal permet llistar i filtrar mitjançant paràmetres GET (ex. `leg_id` per legislatura, `politic_id` per grup polític). `https://videoteca.parlamentodeandalucia.es/people?letter=&key=&leg_id=14&gbody_id=&politic_id=`

-   **Fitxa Individual del Diputat:** Cada diputat té una URL "friendly" (slug) on es detallen les seves metadades. `https://videoteca.parlamentodeandalucia.es/people/aguilera-clavijo-angela`

### 2\. Implicacions per al Projecte

1.  **Construcció de Base de Dades Relacional:** Podrem crear una taula de `Diputats` fent un scraping previ del directori. Posteriorment, els noms extrets de l'API JSON (`"name": "Aguirre Muñoz, Jesús"`) es podran vincular a aquestes fitxes per tenir automàticament el partit i grup parlamentari de cada intervenció.

2.  **Tasques Pendents:**

    -   Investigar si la ruta `/people` funciona exclusivament amb renderitzat HTML (i per tant requereix eines com `BeautifulSoup` o `Scrapy` per extreure les dades) o si, igual que els vídeos, existeix un endpoint intern (`/api/people.json` o similar) que puguem explotar directament per recollir el llistat sencer.

Entrada 3: Disponibilitat de sessions i transcripcions
------------------------------------------------------

**Data:** 22 d'abril de 2026

S'ha identificat la URL de cerca general de vídeos i s'han fet algunes observacions preliminars sobre la disponibilitat de les dades estructurades.

### 1\. URL de Cerca General

La llista de tots els vídeos disponibles es pot trobar i filtrar mitjançant aquesta URL: `https://videoteca.parlamentodeandalucia.es/search?view_type=list&legs_id=3377&gbody_id=&channel_id=&category_id=&tag_id=&date=&date_from=&date_to=&speaker_id=&text=`

### 2\. Disponibilitat de Transcripcions (STT)

Després d'una exploració preliminar, s'ha constatat que les transcripcions (les dades de l'array `stt` detallades a l'Entrada 1) només estan disponibles per a les legislatures més recents:

-   Legislatura 12 (Actual)

-   Legislatura 11

-   Legislatura 10

Això acotarà l'abast temporal inicial del corpus de text per al posterior anàlisi amb NLP.

Entrada 4: Estratègia d'scraping per al catàleg i filtratge de Plens
--------------------------------------------------------------------

**Data:** 22 d'abril de 2026

Després de confirmar que no hi ha una API interna accessible per obtenir el llistat complet de vídeos, s'ha pres una decisió arquitectònica sobre com procedir per aconseguir el catàleg.

### 1\. Mètode d'obtenció del catàleg

S'haurà de desenvolupar un procés de *web scraping* clàssic (ex. amb Python i `BeautifulSoup` o Selenium/Playwright) sobre l'HTML de la pàgina de cerca. L'objectiu d'aquest *scraping* serà extreure els enllaços dels vídeos i, d'ells, deduir l'identificador (en Base64) que posteriorment es traduirà a l'`{ID_MASTER}` per poder atacar l'API del JSON amb les transcripcions.

### 2\. Filtratge exclusiu per sessions de Ple

Per centrar la recerca en els debats principals i ometre l'activitat de comissions o òrgans menors (que poden afegir soroll o no ser l'objectiu de l'estudi), s'ha identificat la URL de cerca exacta aplicant els filtres necessaris.

-   **URL filtrada per a Plens:** `https://videoteca.parlamentodeandalucia.es/search?view_type=list&legs_id=3377&gbody_id=3378&channel_id=&category_id=&tag_id=&date=&date_from=&date_to=&speaker_id=&text=`

-   **Nota Tècnica:** El paràmetre `gbody_id=3378` a la URL es correspon al filtre específic del "Ple", la qual cosa simplificarà l'extracció.

Entrada 5: Obtenció de l'ID Mestre de l'API (El pont de connexió)
-----------------------------------------------------------------

**Data:** 22 d'abril de 2026

S'ha resolt el darrer obstacle tècnic del pipeline d'extracció: com passar de la URL pública del vídeo a l'ID intern necessari per fer la crida a l'API JSON que retorna les transcripcions.

### 1\. La "Pedra de Rosetta" al codi font HTML

En accedir a la pàgina d'un vídeo qualsevol (ex: `/watch?id=OGI2M2F...`), el codi font HTML conté un bloc de JavaScript encarregat de configurar el reproductor. Dins d'aquest bloc es troba l'ID numèric que necessitem.

**Fragment clau extret del codi font HTML:**

```
<!-- JSPLAYLIST -->
<script>
var JSPLAYLIST1=[];;
var JSPLAYLIST1_entrys=1;

JSPLAYLIST1[1] = {};
JSPLAYLIST1[1].sequence=1;
JSPLAYLIST1[1].part='ZjAwYTQwZjQtMzVmYy00YjY0LTliNzAtNGVjMDU1MmFiZjQ4';
// ... variables del reproductor ...
JSPLAYLIST1[1].resources_url='/resources/sheets?published=true&subject_id=27084&subject_type=bitstream&type=media';
JSPLAYLIST1[1].title='Diario Sesiones Pleno 153';
</script>
<!-- JSPLAYLIST END -->

```

### 2\. Mètode d'extracció

L'element decisiu és la variable `resources_url` que conté el paràmetre **`subject_id=27084`**. Aquest número és exactament l'`{ID_MASTER}` per poder interrogar la API `/timeline.json`.

### 3\. Pipeline d'extracció complet actualitzat

La seqüència d'accions per extreure les dades d'una sessió serà la següent:

1.  **Scraping del llistat:** Obtenir la URL del vídeo des de la pàgina del cercador.

2.  **Peticio HTTP al vídeo:** Fer un GET a la URL `/watch?id=...`.

3.  **Parseig Regex:** Aplicar una expressió regular sobre l'HTML de resposta (ex: `subject_id=(\d+)`) per capturar l'ID mestre (ex: `27084`).

4.  **Extracció de l'estructura general (API JSON):** Fer una primera crida a l'endpoint *sense* el paràmetre `stt` (ex: `/api/masters/27084/timeline.json?end=999999999999&start=0`) per recuperar l'esquelet complet de la sessió. D'aquí s'extrauran tots els blocs d'intervencions amb el seu corresponent `start` i `end`.

5.  **Extracció paginada de les transcripcions (STT):** Per evitar respostes JSON massa grans que puguin provocar saturació o talls per part del servidor, s'iterarà sobre la llista obtinguda al punt 4. Per a cada intervenció, es farà una petició específica afegint el paràmetre `stt=records` i fitant els temps (ex: `/api/masters/27084/timeline.json?end=189.793&start=22.390&stt=records`).