Projecte NLP - Parlament d'Andalusia
====================================

Visió General
-------------

Aquest és un projecte de ciència política computacional centrat a extreure, estructurar i analitzar les intervencions dels diputats del Parlament d'Andalusia. La hipòtesi de recerca principal busca analitzar l'evolució discursiva (enquadrament / *framing*) en els debats relacionats amb "Catalunya", prestant especial atenció a possibles efectes de polarització o convergència (efecte contagi) entre diferents legislatures i partits.

El sistema es basa en la transcripció automàtica (STT) provinent de l'API oculta de la Videoteca del Parlament.

⚠️ Instruccions Bàsiques per a Desenvolupadors / Agents IA
----------------------------------------------------------

Si ets un agent d'IA o un desenvolupador que s'incorpora al projecte, **LA TEVA PRIMERA TASCA ÉS LLEGIR EL FITXER `PLAN.md`**.

El fitxer `PLAN.md` és el "Pla Mestre" i conté la font de la veritat per a:

1.  **Els endpoints exactes** de l'API i els mètodes de *scraping* per a resoldre l'identificador dels vídeos (la "Pedra de Rosetta").

2.  **L'arbre de directoris complet**, que s'ha de respectar escrupolosament.

3.  **El** ***Codebook*** **per al LLM**, incloent el JSON Schema exacte que s'ha d'exigir a l'API (OpenAI/Anthropic) en l'etapa d'extracció semàntica.

Punts Clau d'Arquitectura (Llegir abans de programar)
-----------------------------------------------------

-   **Stack Tecnològic:** Estrictament **R** (amb paquets com `httr2`, `rvest`, `jsonlite`, `dplyr`). No utilitzis Python excepte que s'indiqui expressament.

-   **Emmagatzematge:** No hi ha base de dades (SQL/NoSQL). S'utilitza una **arquitectura de fitxers JSON** per a la fase crua, que es consolida posteriorment en un `.parquet` o `.rds` per a l'anàlisi amb `Tidyverse`.

-   **Resiliència:** Qualsevol script que faci peticions de xarxa ha de comprovar si l'arxiu JSON de destí ja existeix al disc dur per evitar repetir feina o perdre el progrés en cas d'error (`tryCatch` és obligatori).

*Si us plau, referiu-vos al `PLAN.md` per a començar a desenvolupar els scripts continguts a la carpeta `00_scripts_R/`.*