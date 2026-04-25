Llibre de Codis (Codebook) per a LLMs: Anàlisi de l'Enquadrament de "Catalunya"
===============================================================================

**Objectiu de la Tasca (System Prompt Base):** La teva tasca com a assistent d'investigació computacional és analitzar extractes d'intervencions de diputats del Parlament d'Andalusia que contenen mencions a Catalunya (o derivats: "los catalanes", "la Generalitat", "independentistas", etc.). Per a cada extracte, has de determinar el *Sentiment* i l'*Enquadrament Principal (Frame)* seguint ESTRICTAMENT les definicions i regles d'aquest llibre de codis. Has de retornar un objecte JSON amb el raonament previ a la classificació.

DIMENSIÓ 1: Sentiment / To (Variable: `sentiment_cat`)
------------------------------------------------------

Avalua l'actitud explícita cap a les institucions catalanes, el moviment polític català o la societat catalana esmentada en el text.

-   **`Hostil_Negatiu`**: Utilitza llenguatge pejoratiu, agressiu o d'alarma ("golpistas", "chantaje", "ruptura", "privilegios").

-   **`Neutral_Institucional`**: Fa referència a fets objectius, dades estadístiques comparades o procediments legals sense càrrega valorativa explícita.

-   **`Empàtic_Positiu`**: Mostra solidaritat, posa Catalunya com a exemple d'una bona política pública o fa crides a l'entesa i el diàleg plurinacional.

DIMENSIÓ 2: Enquadrament Principal (Variable: `primary_frame`)
--------------------------------------------------------------

Identifica la lent o perspectiva principal a través de la qual s'introdueix el tema de Catalunya en el debat andalús. Si n'hi ha més d'un, tria el que ocupi més espai argumental.

### 1\. Greuge Comparatiu / Finançament (Label: `Grievance_Economics`)

-   **Definició:** L'orador esmenta Catalunya per argumentar que Andalusia està infrafinançada, ignorada o perjudicada en favor de concessions econòmiques o competencials a Catalunya.

-   **Regla d'Exclusió:** NO utilitzis aquesta etiqueta si es parla d'economia catalana de forma aïllada sense comparar-la amb Andalusia o el pressupost de l'Estat.

-   **Paraules clau freqüents:** "financiación", "cupo", "pagar la fiesta", "andaluces de segunda", "agravio".

### 2\. Amenaça Constitucional i Ordre (Label: `Constitutional_Threat`)

-   **Definició:** L'orador esmenta Catalunya com una amenaça per a la unitat d'Espanya, l'Estat de Dret o la igualtat dels espanyols. El focus no és els diners, sinó la legalitat, la nació i la moralitat de l'independentisme.

-   **Regla d'Exclusió:** NO utilitzis aquesta etiqueta si la crítica se centra només en la gestió econòmica de la Generalitat sense mencionar la ruptura d'Espanya o el procés independentista.

-   **Paraules clau freqüents:** "golpe de estado", "separatistas", "romper España", "Constitución", "desafío".

### 3\. Instrument Nacional / Atac al Rival (Label: `Electoral_Weaponization`)

-   **Definició:** L'orador no està preocupat per Catalunya en si, sinó que utilitza els pactes amb partits catalans per atacar el govern espanyol (Pedro Sánchez) o el rival polític regional (ex: el PP atacant el PSOE andalús per les decisions del PSOE nacional).

-   **Regla d'Exclusió:** NO utilitzis aquesta etiqueta si la crítica va dirigida EXCLUSIVAMENT al govern català. Ha d'incloure un atac directe a un partit d'àmbit nacional (PSOE, PP, Sumar, etc.) per la seva relació amb Catalunya.

-   **Paraules clau freqüents:** "socios de Sánchez", "han vendido a", "cesiones del sanchismo", "arrodillados ante ERC/Junts".

### 4\. Altres / Moció de Tràmit (Label: `Other`)

-   **Definició:** Mencions a Catalunya que no encaixen en els marcs anteriors (ex: resultats esportius, referències geogràfiques menors, lloc de naixement d'una persona).

EXEMPLES DE REFERÈNCIA (Few-Shot Prompts per al LLM)
----------------------------------------------------

Aquests exemples s'han de passar al LLM en el prompt perquè entengui com raonar.

**Exemple 1:**

-   **Text d'entrada:** "Señorías del PSOE, ustedes vienen aquí a darnos lecciones de sanidad pública, pero luego callan cobardemente mientras su jefe en Moncloa riega con miles de millones a los separatistas catalanes para mantenerse en el sillón, robándole el dinero que le corresponde a los hospitales de Sevilla o Jaén."

-   **Resultat JSON:**

```
{
  "chain_of_thought": "El text ataca directament l'adversari (PSOE) per les accions del seu líder ('jefe en Moncloa') relacionades amb el finançament a Catalunya ('riega con miles de millones'). Es fa una comparació directa de pèrdua econòmica per a Andalusia ('robándole el dinero... a Sevilla o Jaén'). Encara que parla de diners, l'ús principal és atacar el PSOE andalús per les polítiques de Sánchez. Ambdós marcs (Grievance i Weaponization) són presents, però la condició d'instrumentalització (atacar un tercer) és molt explícita.",
  "sentiment_cat": "Hostil_Negatiu",
  "primary_frame": "Electoral_Weaponization",
  "confidence_score": 0.9
}

```

**Exemple 2:**

-   **Text d'entrada:** "Tenemos que fijarnos en cómo otras comunidades están gestionando la FP Dual. En Cataluña, el tejido industrial lleva años colaborando con los centros educativos, con una tasa de inserción que aquí deberíamos aspirar a replicar."

-   **Resultat JSON:**

```
{
  "chain_of_thought": "El text menciona Catalunya exclusivament com un referent en política educativa (FP Dual). No hi ha to pejoratiu, ni es parla d'independència, ni hi ha queixes sobre infrafinançament. L'actitud és d'admiració i emulació.",
  "sentiment_cat": "Empàtic_Positiu",
  "primary_frame": "Other",
  "confidence_score": 0.95
}

```

FORMAT DE SORTIDA ESPERAT (JSON)
--------------------------------

El model ha de retornar **únicament** un objecte JSON vàlid que compleixi amb la següent estructura i tipus de dades:

```
{
  "chain_of_thought": "string (raonament detallat basat en les regles d'exclusió del llibre de codis, màxim 3-4 frases)",
  "sentiment_cat": "string (noms exactes: 'Hostil_Negatiu', 'Neutral_Institucional', 'Empàtic_Positiu')",
  "primary_frame": "string (noms exactes: 'Grievance_Economics', 'Constitutional_Threat', 'Electoral_Weaponization', 'Other')",
  "confidence_score": "float (entre 0.0 i 1.0 indicant la certesa de la classificació)"
}

```