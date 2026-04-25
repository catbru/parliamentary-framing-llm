Avaluació i Ús d'LLMs en Textos Polítics
========================================

Aquest document resumeix l'estat de l'art pel que fa a l'ús de Large Language Models (LLMs) com a eines de mesura per a conceptes en ciència política, l'enquadrament (framing) i el posicionament (stance detection).

1\. El paradigma dels "Codebook LLMs" (Halterman & Keith, 2024/2025)
--------------------------------------------------------------------

El *paper* "Codebook LLMs: Evaluating LLMs as Measurement Tools for Political Science Concepts" aborda el problema central de la validesa de mesura en el pas de l'anotació humana a la intel-ligència artificial.

### Què demostra l'article?

-   **El perill del "Zero-Shot" ingenu:** Tradicionalment, es confiava en què els models (com ChatGPT) sabien "de fàbrica" què era un terme ("universal label assumption"). Halterman i Keith demostren que, davant d'una categoria complexa (com pot ser l'enquadrament d'una política pública), els models oberts no segueixen bé les regles d'exclusió dels llibres de codis si no s'entrenen específicament.

-   **Formatatge del llibre de codis:** Perquè un LLM pugui classificar bé, el llibre de codis tradicional de ciència política s'ha de traduir a una estructura amigable per a la màquina: *Etiqueta* + *Definició curta* + *Clarificacions (incloent-hi exclusions clares, ex. "Això NO és X si...")* + *Exemples positius i negatius amb justificació (Few-shot)*.

-   **Supervised Fine-Tuning (SFT):** L'article prova empíricament que l'opció més robusta per a l'anàlisi de text polític rigorós no és només fer "prompting", sinó afinar un model obert (ex. Mistral) mitjançant tècniques de baix cost (QLoRA) amb centenars d'exemples prèviament validats.

### Implicacions per al Parlament d'Andalusia

Si vols utilitzar l'anàlisi d'enquadrament (Metodologia 4) per veure com ha canviat el discurs:

1.  No podràs limitar-te a donar-li les categories del *Comparative Agendas Project* i ja està. Hauràs de crear un llibre de codis detallat per a l'LLM.

2.  Hauràs de fer una avaluació manual cega d'almenys 100-200 intervencions per mesurar l'acord inter-codificador entre tu i el teu model.

2\. Altres aplicacions de Stance / Framing en el Món Real
---------------------------------------------------------

La recerca en aquest camp està explotant ara mateix. Aquestes són algunes referències rellevants de mètodes d'extracció de posicionament amb LLMs en els últims mesos:

### A. Target-Stance Extraction (TSE) i Polítiques Complexes

-   **"Stay Tuned: Improving Sentiment Analysis and Stance Detection Using Large Language Models"** (Cambridge University Press, Desembre 2025).

    -   *Relevància:* Demostren que les tècniques de "Chain-of-Thought" (fer que l'LLM raoni l'argumentació abans d'emetre l'etiqueta) milloren dràsticament l'acord amb els codificadors humans. També proven que introduir l'afiliació partidista com a variable ("Cross-target tuning") ajuda el model a captar millor el posicionament latent.

### B. El salt dels models menors i eficients

-   **"Political DEBATE: Efficient Zero-Shot and Few-Shot Classifiers for Political Text"** (Political Analysis, 2025).

    -   *Relevància:* Els autors desenvolupen un model basat en BERT especialitzat en text polític que, amb només 10-25 exemples d'entrenament, supera models generatius gegants en la detecció del to polític i els temes. Seria una molt bona alternativa si tens pocs recursos de computació.

### C. Detecció d'Actors i "Stance" en Discurs Polític General

-   **"Promises and pitfalls of using LLMs to identify actor stances in political discourse"** (Angst et al., Novembre 2025).

    -   *Relevància:* Un test empíric representatiu sobre el món real, analitzant posicions de suport/rebuig cap a temes concrets (no declaracions aïllades). Adverteixen que la complexitat semàntica de la ironia, l'absència de context i el biaix del propi LLM obliguen l'investigador a tenir una avaluació en un domini hiper-específic abans de llançar l'extracció a gran escala.

### D. Social Listening i Framing Obert

-   **"From Chaos to Clarity: Using LLMs for Political Social Listening"** (Jones, Octubre 2025).

    -   *Relevància:* Mentre que abans es classificava una sentència sencera sota un marc ("economia"), ara s'utilitzen crides estructurades (JSON) on s'extreu: l'entitat, el marc temàtic aplicat i la intensitat de la polarització en la mateixa sentència.