Prompt Mestre per a la Redacció de l'Article Acadèmic (Quarto/PDF)
==================================================================

**Context del Rol:** Ets un acadèmic d'alt nivell en Ciència Política, expert en anàlisi quantitativa i política territorial. Els autors de l'article són Claudi Sonet, Gemma Bessons i Geppetto Openini. El to ha de ser formal, analític, rigorós i propi d'una revista de primer nivell (Q1) com *Political Analysis*, *West European Politics* o *Journal of Communication*.

**REQUISITS TÈCNICS I LINGÜÍSTICS:**

-   **Idioma de l'article:** L'article sencer s'ha d'escriure en **ANGLÈS ACADÈMIC** (Academic English).

-   **Format:** Genera un fitxer Quarto (`.qmd`) optimitzat per a una sortida en **PDF**.

-   **Localització:** Tots els productes (el `.qmd` i fitxers auxiliars) s'han de desar a la carpeta `article/`.

1\. FRONTMATTER (YAML)
----------------------

Configura el document amb el títol, autors (Marc Sanjaume-Calvet i Roger Sanjaume i Calvet), afiliacions i format `pdf` amb taula de continguts i numeració de seccions.

2\. ABSTRACT
------------

Redacta un resum executiu que plantegi el títol: *"Catalonia as an Electoral Weapon: Discursive Framing and Territorial Instrumentalization in the Parliament of Andalusia (XII Legislature)"*. Ha d'emfatitzar la paradoxa de l'externalització del debat regional i la innovació de mesura mitjançant LLMs sota protocols de validació acadèmica.

3\. INTRODUCTION: THE ANDALUSIAN ECHO CHAMBER
---------------------------------------------

-   **The Puzzle:** Per què un parlament regional dedica el 8% de les seves intervencions a una altra regió?

-   **Externalització i Identitat:** Andalusia ha construït la seva identitat en relació/oposició a les "nacionalitats històriques" (Cita: Pérez Yruela, 1998; Montabes et al., 2022).

-   **Context Polític:** La XII Legislatura com a laboratori: majoria absoluta del PP andalús en contrast amb la dependència del govern central dels pactes amb l'independentisme català.

4\. THEORETICAL FRAMEWORK (Integració Narrativa)
------------------------------------------------

Desenvolupa les següents dimensions teòriques:

1.  **Framing:** Com les elits seleccionen aspectes de la realitat per promoure interpretacions causals (Cita: Entman, 1993; Chong & Druckman, 2007).

2.  **Territorial Grievance:** La competència interregional per recursos i el discurs de la desigualtat financera en sistemes descentralitzats (Cites: López-Laborda et al., 2006; Amat, 2012).

3.  **Affective Polarization & Legitimacy:** L'ús de la qüestió territorial per cohesionar el bloc propi ("out-party dislike"). Catalunya com a factor estructurant de la legitimitat de l'Estat (Cites: Miller & Torcal, 2020; Sanjaume-Calvet, 2020; Rodon, 2023).

5\. DATA AND METHODOLOGY (Rigor Metodològic)
--------------------------------------------

-   **Corpus:** 9.942 intervencions de la XII Legislatura.

-   **Prospecció de Regex:** Explica que es va crear un sub-corpus de fragments (+/- 200 paraules al voltant de "Catalunya") on un LLM (GPT) va extreure inductivament una llista de formes de referir-se a Catalunya per refinar el regex de detecció.

-   **Validació i Blind Analysis:** Justifica la mesura seguint el marc de **Halterman i Keith (2025)** sobre LLMs com a eines de mesura. Destaca que la classificació va ser **"cega"**: el model només va rebre el text de la intervenció, sense saber el diputat ni el partit, eliminant biaixos de coneixement previ.

-   **Variables:** Sentiment (Hostil, Neutral, Empàtic) i Frame (Electoral, Constitucional, Econòmic, Positiu, Altres).

6\. RESULTS: THE ANATOMY OF HOSTILITY
-------------------------------------

Itera sobre les dades dels informes per redactar l'anàlisi:

-   **Intensity:** El 8% global vs el 15% de Vox.

-   **The Sentiment Gap:** La fractura entre l'hostilitat de la dreta (>79%) i la neutralitat de l'esquerra (68-83%).

-   **Divergence in the Right-Wing Block:**

    -   **PP (Traditional Right):** Pivot cap al marc de `Grievance_Economics` (25,9%), vinculant Catalunya al finançament i al greuge regional.

    -   **Vox (Far Right):** Pivot cap al marc de `Constitutional_Threat` (31,2%), amb un to alarmista sobre la unitat nacional i l'ordre social.

-   **Electoral Weaponization:** Com el frame dominant (50% en la dreta) serveix per atacar el rival nacional.

7\. DISCUSSION: STRATEGIC CATALANOPHOBIA
----------------------------------------

-   **Concept:** Desenvolupa la idea de la "Catalanofòbia Estratègica" com a eina de governabilitat que substitueix el debat sobre la gestió interna per la confrontació externa.

-   **Impacte:** L'erosió de la cohesió del model autonòmic quan els parlaments regionals actuen com a plataformes de partit nacional (Cita: Astudillo & Pallarès, 2013).

8\. REFERENCES (Llista obligatòria per a l'IA)
----------------------------------------------

Assegura't d'incloure i citar correctament:

-   Amat, F. (2012). *South European Society and Politics*.

-   Entman, R. M. (1993). *Journal of Communication*.

-   Halterman, A., & Keith, K. A. (2025). *Political Analysis*.

-   Miller, L., & Torcal, M. (2020). *South European Society and Politics*.

-   Rodon, T. (2023). *West European Politics*.

-   Sanjaume-Calvet, M. (2020). Dimension moral del conflicte territorial.

-   Astudillo & Pallarès (2013). Parlaments regionals com a caixa de ressonància.

**Instruccions d'execució:** Redacta el text en paràgrafs acadèmics, no punts. Integra les figures (Figure 1, 2, etc.) en el text narratiu de manera que el lector entengui l'evidència empírica mentre llegeix.