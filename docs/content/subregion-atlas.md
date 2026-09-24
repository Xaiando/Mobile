# Sub-region Atlas

| | |
|---|---|
| **Status** | Study map and content plan for backlog tasks G10–G13, researched on 2026-09-24. The lists are the planned scope. Each task checks its lists against the register named in the region's sheet, and every item stays `unverified` until an expert review (D3). |
| **Design** | [geography.md](../design/geography.md) (map model, formats, sources) · [question-system.md](../design/question-system.md) (formats, completeness) · decisions GEO-15 to GEO-18 in [architecture-audit.md](../architecture-audit.md) §15 |
| **Companion** | [spaetburgunder-study-tree.md](spaetburgunder-study-tree.md): the deep dive into one grape and one country |

The famous regions are learnt through their sub-regions. A candidate must answer:

- where Pauillac lies, and which commune borders it;
- which Côte de Nuits village comes after Chambolle-Musigny, going south;
- which Barolo communes are wholly inside the zone;
- which Willamette Valley AVA the Van Duzer winds cool.

This atlas turns each famous region into a map-based study unit: a tree of its sub-regions, the rivers and landforms that explain it, the levels each track needs, the drills, and the register that makes each fact checkable. As everywhere in the app, a map question practises the same item as its text form (GEO-1).

---

## 1. Principles

| # | Principle | Why |
|---|---|---|
| 1 | **Legal units are areas; informal areas are labelled as such (GEO-15).** A sub-region is drawn as an area only when a legal register defines it: an AOC specification, a *disciplinare*, a *pliego*, a DAC regulation, 27 CFR part 9, a GI register, or a German vineyard register. Traditional areas are node type `informal_area`. Examples: Bordeaux's Left and Right Banks, Champagne's Côte des Blancs, Marlborough's Awatere Valley. They are drawn only from a cited public definition, such as a commune list; otherwise they are a labelled point. The legend says "traditional area, not a legal unit". | Learners need these areas, but an app must never present them as appellations. An "appellation" question never offers an `informal_area` as an answer. |
| 2 | **Nesting follows the register (GEO-16).** `LOCATED_IN` chains mirror the legal nesting: Oakville is in Napa Valley, which is in North Coast. A unit inside two parents has one location item per parent: Los Carneros (Napa and Sonoma), Walla Walla Valley (Washington and Oregon). A map question grades the item whose parent frames it. | GEO-6 assumed one parent. Real registers overlap. |
| 3 | **Levels per track are editorial (L-14).** Each sheet proposes which levels WSET Level 3, CMS Certified and the atlas map. These become `minimum_depth` and importance in the mappings; they are judgements, not syllabus text. | The same map serves each track at its own depth (GEO-4). |
| 4 | **Complete sets need assertions (QF-8).** "Tap all six communal appellations of the Haut-Médoc" is generated only when a completeness assertion cites the register. | Multi-answer drills must be right by construction. |
| 5 | **Registers change (GEO-17).** Lists carry `valid_from` and cite the register with its date. A change retires rows (`valid_until`) and never deletes them (V-2). Recent examples: Rioja Baja renamed Rioja Oriental; Crystal Springs of Napa Valley added in 2024; Bannockburn registered in 2022; the Chianti Classico UGAs from 2023; the Vino Nobile Pievi from 2025. | Knowing what changed is itself examinable. |
| 6 | **Open geometry or points (GEO-5, GEO-9).** Each country uses the open sources of geography §6, or those its atlas task records. Without an open shape, a unit is a point at a gazetteer or municipal label point. An area built from communes is the legal *geographical area*, not the vineyard, and the legend says so (GEO-10). | Licences, and honesty about approximation. |

---

## 2. Drills

Every drill is a generic format ([geography.md](../design/geography.md) §4). The atlas tasks add data, not formats.

| Drill | Format (task) | Example | Items graded |
|---|---|---|---|
| **Locate** | `map_locate` (G4) | "Tap Pauillac" on the Médoc map | Pauillac's location item |
| **Identify** | `map_identify` (G4) | Saint-Julien highlighted → name it (MCQ, then typed at higher depth) | the same item |
| **Hierarchy drill** | `map_drill` (G5) | Bordeaux → Médoc → Haut-Médoc → Pauillac | each level's location item |
| **Order along a line** | `ordering` with a map prompt (G5) | Côte de Nuits villages north to south; Middle Mosel villages downstream | each element's location item |
| **Neighbours** | `map_locate` with `BORDERS` (G8) | "Tap a village bordering Chambolle-Musigny" | the `BORDERS` item tapped |
| **Complete the set** | `map_multi_locate` (G8), `multiple_response` (Q2) | "Tap all ten Beaujolais crus" | each member's item, with the assertion |
| **Bank and side** | MCQ or `map_identify` over informal areas (G4) | "Left Bank or Right Bank: Pomerol?"; "Which bank of the Rhône is Cornas on?" | `LOCATED_IN` to an informal area; `LIES_ALONG` with a side |
| **Rivers and landforms** | `map_locate` (G6) | "Tap the river whose mists make Sauternes' noble rot" (the Ciron) | `LIES_ALONG`, `MODERATED_BY` |
| **Soil on the map** | `map_locate` with `HAS_SOIL` (G7) | "Tap a Chablis Grand Cru climat" | the soil item of the node tapped |
| **Map deduction** | `reasoning` with a map prompt (G9) | A gravel bank on a tidal estuary at 45° N → most plausible grape | chain items |
| **Speed round** | timed drill (S1) | 60 seconds, blank map, ten taps | as for locate |

**Progression.** The ladder (F4, GEO-8) moves each item from the labelled map to the outline map, then the minimal map, then the blank map zoomed out, as its stability grows.

---

## 3. Region sheets

Each sheet gives the **tree**, the **features** that explain it, the **levels** per track (L3 = WSET Level 3, CMS = CMS Certified, Atlas = everything else), the **register** to verify against and the **geometry** source.

- **Lists.** A list followed by *(to verify)* was compiled from secondary material and must be checked item by item. Other lists are well established, but the task still checks them.
- **Reading the levels column.** Each track includes the levels before it: CMS includes L3, and Atlas includes CMS.

### 3.1 France (task G10)

**Register:** the INAO specifications (*cahiers des charges*) and the INAO geographical areas. **Geometry:** IGN ADMIN EXPRESS communes with INAO commune lists; INAO parcel delimitations for crus where published (Licence Ouverte, geography §6).

#### Bordeaux

| Level | Units |
|---|---|
| Informal areas | Left Bank (Médoc, Graves); Right Bank (Libournais); Entre-Deux-Mers, between the Garonne and the Dordogne |
| Médoc peninsula | AOC Médoc (north) and AOC Haut-Médoc (south) |
| Haut-Médoc communal AOCs | **Six:** Saint-Estèphe, Pauillac, Saint-Julien and Margaux (north to south along the Gironde), with Listrac-Médoc and Moulis-en-Médoc inland |
| Graves | Graves, Pessac-Léognan; sweet wines: Sauternes, Barsac, Cérons |
| Right Bank | Saint-Émilion and Saint-Émilion Grand Cru; the satellites Montagne-, Lussac-, Puisseguin- and Saint-Georges-Saint-Émilion; Pomerol, Lalande-de-Pomerol, Fronsac, Canon-Fronsac |
| Côtes | Côtes de Bordeaux, with Blaye, Cadillac, Castillon, Francs and Sainte-Foy; Côtes de Bourg |
| Sweet wines across the Garonne from Sauternes | Loupiac, Cadillac, Sainte-Croix-du-Mont |

- **Features:** the Gironde estuary, Garonne, Dordogne and Isle (at Libourne); the Ciron, whose cool water meeting the Garonne gives autumn mists and noble rot; the Atlantic; the Landes pine forest.
- **Levels:**
  - L3: the banks, Médoc and Haut-Médoc, the four river communes, Graves, Pessac-Léognan, Sauternes and Barsac, Saint-Émilion, Pomerol, Entre-Deux-Mers and the Côtes;
  - CMS: Listrac, Moulis, Fronsac, Lalande-de-Pomerol and the satellites;
  - Atlas: every AOC.
- **Signature drills:** complete the six communal AOCs; order the four river communes north to south; left or right bank.

#### Burgundy and Beaujolais

| Level | Units |
|---|---|
| Areas | Chablis and the Grand Auxerrois; Côte de Nuits and Côte de Beaune (together the Côte d'Or); Côte Chalonnaise; Mâconnais. Beaujolais has its own sheet below. |
| Chablis | Petit Chablis, Chablis, Chablis Premier Cru, Chablis Grand Cru. The seven Grand Cru climats: Blanchot, Bougros, Les Clos, Grenouilles, Preuses, Valmur, Vaudésir. |
| Côte de Nuits village AOCs, north to south | Marsannay, Fixin, Gevrey-Chambertin, Morey-Saint-Denis, Chambolle-Musigny, Vougeot, Vosne-Romanée, Nuits-Saint-Georges. Côte de Nuits-Villages covers other communes (*to verify* the commune list). |
| Côte de Beaune village AOCs, roughly north to south | Ladoix, Pernand-Vergelesses, Aloxe-Corton, Chorey-lès-Beaune, Savigny-lès-Beaune, Beaune, Pommard, Volnay, Monthélie, Auxey-Duresses, Saint-Romain, Meursault, Blagny, Puligny-Montrachet, Chassagne-Montrachet, Saint-Aubin, Santenay, Maranges |
| Grands crus | 33 in Burgundy: 24 in the Côte de Nuits, 8 in the Côte de Beaune and Chablis Grand Cru as one (*to verify*). Mapped as `site`s at Atlas level. |
| Côte Chalonnaise | Bouzeron, Rully, Mercurey, Givry, Montagny |
| Mâconnais | Mâcon and Mâcon-Villages; Viré-Clessé; Saint-Véran; Pouilly-Fuissé, with premiers crus from the 2020 vintage (*to verify*); Pouilly-Loché; Pouilly-Vinzelles |

- **Features:** the Côte d'Or escarpment with its east- and south-east-facing slopes; the Saône plain; the Hautes-Côtes behind; the combes; the Serein at Chablis; Kimmeridgian marl.
- **Levels:**
  - L3: the areas; Chablis and its Grand Cru; the key villages (Gevrey, Vosne, Nuits; Beaune, Pommard, Volnay, Meursault, Puligny, Chassagne); the main Chalonnaise and Mâconnais AOCs;
  - CMS: every Côte d'Or village, and the Côte de Nuits grands crus by name;
  - Atlas: all 33 grands crus as sites.
- **Signature drills:** order the Côte de Nuits north to south; neighbours of Chambolle-Musigny; tap a Chablis Grand Cru climat.

#### Beaujolais

- **Crus:** ten, roughly north to south: Saint-Amour, Juliénas, Chénas, Moulin-à-Vent, Fleurie, Chiroubles, Morgon, Régnié, Côte de Brouilly (on Mont Brouilly) and Brouilly (around it).
- **Other AOCs:** Beaujolais-Villages, Beaujolais.
- **Features:** granite in the north, where the crus are; the Saône to the east.
- **Levels:** L3 and CMS: the crus as a set; Atlas: order and neighbours.
- **Signature drill:** tap all ten crus (a completeness assertion).

#### Champagne

- **One AOC, Champagne**, alongside Coteaux Champenois and Rosé des Riceys.
- **Traditional areas** (`informal_area`), as described by the Comité Champagne: Montagne de Reims, Vallée de la Marne, Côte des Blancs, Côte de Sézanne and Côte des Bar (*to verify* the list the Comité uses).
- **Grand Cru communes: 17.** Ambonnay, Avize, Aÿ, Beaumont-sur-Vesle, Bouzy, Chouilly, Cramant, Louvois, Mailly-Champagne, Le Mesnil-sur-Oger, Oger, Oiry, Puisieulx, Sillery, Tours-sur-Marne, Verzenay, Verzy. The Premier Cru communes are listed in the specification (*to verify* the count).
- **Features:** the Marne; Reims and Épernay; chalk; the Aube's Kimmeridgian marls in the Côte des Bar.
- **Levels:** L3: the traditional areas; CMS: the best-known Grand Cru villages (Aÿ, Bouzy, Ambonnay, Verzenay, Cramant, Avize, Le Mesnil-sur-Oger); Atlas: all 17.

#### Loire

- **Areas** (informal): Pays Nantais, Anjou-Saumur, Touraine, Centre-Loire.
- **AOCs:**
  - Muscadet Sèvre et Maine, with its *crus communaux* (*to verify* the list);
  - Savennières, Coteaux du Layon, Quarts de Chaume, Bonnezeaux;
  - Saumur, Saumur-Champigny;
  - Chinon, Bourgueil, Saint-Nicolas-de-Bourgueil;
  - Vouvray, Montlouis-sur-Loire;
  - Sancerre, Pouilly-Fumé, Menetou-Salon, Quincy, Reuilly.
- **Features:** the Loire and its tributaries: the Sèvre Nantaise and the Maine; the Layon; the Vienne at Chinon; the Cher.
- **Signature drill:** order upstream to downstream: Sancerre, Vouvray, Chinon, Saumur, Savennières, Muscadet.

#### Rhône

- **Northern Rhône, north to south:**
  - right (west) bank: Côte-Rôtie, Condrieu, Château-Grillet, Saint-Joseph, Cornas, Saint-Péray;
  - left (east) bank: Hermitage and Crozes-Hermitage.
- **Southern Rhône:** Châteauneuf-du-Pape, Gigondas, Vacqueyras, Rasteau, Cairanne, Vinsobres and Beaumes-de-Venise; Lirac and Tavel on the right bank; Côtes du Rhône Villages with its named villages (*to verify* the count).
- **Features:** the Rhône; the Mistral; the Dentelles de Montmirail; Mont Ventoux.
- **Levels:**
  - L3: north against south, the main northern crus, Châteauneuf, Gigondas, Vacqueyras, Tavel, Lirac;
  - CMS: Château-Grillet, Saint-Péray, Rasteau, Cairanne, Vinsobres, Beaumes-de-Venise;
  - Atlas: the named Côtes du Rhône villages.
- **Signature drill:** which bank?

#### Alsace

- **AOCs:** Alsace, Alsace Grand Cru (51 grands crus), Crémant d'Alsace.
- **Two départements:** Bas-Rhin (north) and Haut-Rhin (south).
- **Pinot Noir grands crus.** Since the 2022 vintage, Pinot Noir may carry Grand Cru status in Hengst and Kirchberg de Barr (*to verify* in the specification).
- **Features:** the Vosges and their rain shadow (Colmar); the Rhine to the east.
- **Levels:** L3: the region and the Vosges; CMS: selected grands crus; Atlas: all 51 as sites.

### 3.2 Italy (task G11)

**Register:** the MASAF *disciplinari* for each DOC and DOCG. **Geometry:** ISTAT communes (CC BY, version to confirm at download). Where a zone takes only part of a commune, the whole commune is drawn and the legend says so (GEO-10).

#### Piedmont

- **Areas:** Langhe; Roero, on the left bank of the Tanaro; Monferrato; Alto Piemonte.
- **Barolo DOCG: 11 communes.**
  - Barolo, Castiglione Falletto and Serralunga d'Alba lie wholly in the zone.
  - La Morra, Monforte d'Alba, Verduno, Novello, Grinzane Cavour, Diano d'Alba, Cherasco and Roddi lie partly in it (*to verify*).
  - Its *menzioni geografiche aggiuntive* (MGAs) become `site`s at Atlas level (*to verify* the count).
- **Barbaresco DOCG:** Barbaresco, Neive, Treiso and part of Alba (San Rocco Seno d'Elvio). Its MGAs are sites at Atlas level.
- **Other DOCGs:** Roero, Barbera d'Asti, Nizza, Gavi, Asti and Moscato d'Asti, Dogliani; Gattinara and Ghemme in the Alto Piemonte.
- **Features:** the Tanaro; Alba; the Alps around the region.
- **Levels:** L3: Barolo, Barbaresco, Barbera d'Asti, Gavi, Asti; CMS: the Barolo communes; Atlas: MGAs.
- **Signature drills:** tap the three communes wholly inside Barolo; locate Barbaresco relative to Alba.

#### Tuscany

- **Chianti Classico DOCG: 11 UGAs** (*unità geografiche aggiuntive*), for Gran Selezione, in the Gazzetta Ufficiale since 1 July 2023: Castellina, Castelnuovo Berardenga, Gaiole, Greve, Lamole, Montefioralle, Panzano, Radda, San Casciano, San Donato in Poggio, Vagliagli.
- **Chianti DOCG: seven subzones.** Colli Aretini, Colli Fiorentini, Colli Senesi, Colline Pisane, Montalbano, Montespertoli, Rufina.
- **Brunello and Rosso di Montalcino:** the commune of Montalcino.
- **Vino Nobile di Montepulciano: 12 *Pievi*** (UGAs), decree published on 5 February 2025. Ascianello, Argiano, Badia, Caggiole, Cerliana, Cervognano, Gracciano, Le Grazie, San Biagio, Sant'Albino, Valardegna, Valiano.
- **The coast and other DOCGs:** Bolgheri and Bolgheri Sassicaia; Morellino di Scansano; Carmignano; Vernaccia di San Gimignano.
- **Features:** the Apennines, the Arno, Florence and Siena; the Tyrrhenian coast.
- **Levels:**
  - L3: Chianti against Chianti Classico, Rufina and Colli Senesi, Montalcino, Montepulciano, Bolgheri, Maremma;
  - CMS: all seven Chianti subzones, Carmignano;
  - Atlas: the 11 UGAs and the 12 Pievi.

#### Veneto

- **Valpolicella:** the Classico communes of Fumane, Marano, Negrar, Sant'Ambrogio and San Pietro in Cariano; Valpantena (*to verify*).
- **Soave Classico:** Soave and Monteforte d'Alpone (*to verify*).
- **Prosecco:** Conegliano Valdobbiadene, with Cartizze, and Asolo.
- **Lake Garda:** Bardolino, Lugana.
- **Levels:** L3: Valpolicella, Soave, Prosecco; CMS: Classico zones, Cartizze; Atlas: the communes.

### 3.3 Spain and Portugal (task G11)

**Register:** Spain's *pliegos de condiciones*; Portugal's IVV and IVDP rules. **Geometry:** open national boundary sources, researched by G11 (L-25); otherwise points (GEO-9).

#### Spain

- **Rioja (DOCa): three zones.**
  - Rioja Alta, Rioja Alavesa and Rioja Oriental, which was called Rioja Baja until 2018.
  - Village (*municipio*) and single-vineyard (*viñedo singular*) indications (*to verify* dates and lists).
  - **Features:** the Ebro and its tributaries; the Sierra de Cantabria as a shelter to the north.
- **Ribera del Duero (DO):** the Duero; four provinces (Burgos, Valladolid, Soria, Segovia); the high plateau.
- **Priorat (DOQ):** *llicorella* slate; village wines (*Vi de Vila*), *to verify* the list; Montsant surrounds it.
- **Rías Baixas (DO): five subzones.** Val do Salnés, Condado do Tea, O Rosal, Soutomaior, Ribeira do Ulla.
- **Jerez-Xérès-Sherry (DO):**
  - the ageing towns of the "triangle": Jerez de la Frontera, El Puerto de Santa María and Sanlúcar de Barrameda (Manzanilla);
  - albariza soil; the Guadalquivir; the Levante and Poniente winds.
- **Cava:** the zoning of 2020 (*to verify* the zones).
- **Levels:**
  - L3: the Rioja zones, Ribera, Priorat, Rías Baixas, the Sherry towns;
  - CMS: the Rías Baixas subzones, Montsant;
  - Atlas: villages and single-vineyard wines.

#### Portugal

- **Douro: three subregions**, from west to east: Baixo Corgo, the wettest; Cima Corgo, around Pinhão; Douro Superior, the driest, reaching the Spanish border.
  - **Features:** schist; the Douro and its tributaries (Corgo, Pinhão, Tua, Távora); the Serra do Marão rain shadow.
- **Vinho Verde: nine subregions.** Amarante, Ave, Baião, Basto, Cávado, Lima, Monção e Melgaço, Paiva, Sousa.
- **Alentejo: eight subregions.** Borba, Évora, Granja-Amareleja, Moura, Portalegre, Redondo, Reguengos, Vidigueira (*to verify*).
- **Also:** Dão, Bairrada, Madeira.
- **Levels:** L3: the Douro subregions (west to east), Vinho Verde, Madeira; CMS: Monção e Melgaço; Atlas: every subregion.
- **Signature drill:** order the Douro subregions west to east, and match each to its rainfall.

### 3.4 Germany, Austria and Switzerland (task G12)

#### Germany

**Register:** the Wine Act's 13 regions [WeinG §3]; each state's vineyard register (*Weinbergsrolle*) for Bereiche, Großlagen and Einzellagen.

**Geometry:**
- BKG VG250 municipalities (dl-de/by-2-0);
- the RLP Einzellagen dataset for the Ahr, Mosel, Mittelrhein, Nahe, Pfalz and Rheinhessen (dl-de/by-2-0);
- Baden-Württemberg, Hessen, Bayern, Sachsen, Sachsen-Anhalt and Thüringen: open register data to be researched by G12 (L-25), otherwise points.

| Level | Units |
|---|---|
| Regions (13) | Ahr, Baden, Franken, Hessische Bergstraße, Mittelrhein, Mosel, Nahe, Pfalz, Rheingau, Rheinhessen, Saale-Unstrut, Sachsen, Württemberg |
| Bereiche (*to verify* against the registers) | Baden 9 · Mosel 6 · Württemberg 6 · Rheinhessen 3 · Pfalz 2 · Rheingau 1 · Ahr 1 · Nahe 1 · Mittelrhein 2 · Hessische Bergstraße 2 · Saale-Unstrut 3 · Sachsen 2 · Franken (reorganised; take the current list from the Bavarian register) |
| Villages and sites | The Spätburgunder pack's sites ([spaetburgunder-study-tree.md](spaetburgunder-study-tree.md) §4); for Riesling, the classic villages below |

- **Features:**
  - rivers: the Rhine, Mosel, Saar, Ruwer, Nahe, Main, Neckar, Ahr, Tauber, Elbe, Saale and Unstrut;
  - landforms: the Kaiserstuhl, Haardt and Palatinate Forest, Taunus, Hunsrück, Odenwald and Black Forest; the Vosges across the border; the Upper Rhine Graben;
  - Lake Constance.
- **Villages along a line** (*to verify* each order with label points):
  - the Middle Mosel downstream: Trittenheim, Piesport, Brauneberg, Bernkastel-Kues, Graach, Wehlen, Zeltingen, Ürzig, Erden;
  - the Rheingau's riverside villages from west to east: Lorch, Assmannshausen, Rüdesheim, Geisenheim, Winkel, Oestrich, Hattenheim, Erbach, Eltville, Walluf, and Hochheim on the Main. Inland villages such as Johannisberg, Kiedrich and Rauenthal are located but not ordered.
- **Levels:**
  - L3: the regions that matter most (Mosel, Rheingau, Rheinhessen, Pfalz, Nahe, Baden, Franken, Ahr, Württemberg) and their rivers;
  - CMS: famous villages and Bereiche;
  - Atlas and pack: all Bereiche, villages and the pack's sites.
- **Signature drills:** "Tap every region where Spätburgunder leads" (the Ahr and Baden, as a completeness assertion over the 2024 survey); order the Mosel villages downstream; the Rheingau from west to east.

#### Austria

- **Register:** the Austrian wine law and its DAC regulations, in the federal legal information system (RIS).
- **Geometry:** open municipal boundaries, to be researched by G12 (L-25), otherwise points.
- **Tree:** federal states → 18 DACs (all specific wine-growing areas had DAC status by 2023):
  - Niederösterreich: Weinviertel, Traisental, Kremstal, Kamptal, Carnuntum, Wachau, Wagram, Thermenregion;
  - Burgenland: Mittelburgenland, Leithaberg, Eisenberg, Neusiedlersee, Rosalia, and Ruster Ausbruch (sweet wine only);
  - Steiermark: Südsteiermark, Vulkanland Steiermark, Weststeiermark;
  - Wien: Wiener Gemischter Satz.
- **Features:** the Danube, with the Kamp and the Traisen; Lake Neusiedl; the Leitha Mountains; the Pannonian plain.
- **Sites.** The Wachau's single vineyards (*Rieden*) are sites at Atlas level. *To verify:* Austria's vineyard classification introduced in 2024.
- **Levels:**
  - L3: the Danube DACs (Wachau, Kremstal, Kamptal), Weinviertel, Neusiedlersee, Mittelburgenland, Südsteiermark;
  - CMS: Leithaberg, Eisenberg, the Thermenregion (Pinot Noir, St. Laurent);
  - Atlas: all 18, and the Rieden.

#### Switzerland

- **Register:** cantonal AOC rules.
- **Geometry:** federal open boundaries (*to verify* the licence, L-25).
- **Tree:** six wine regions (*to verify*): Valais, Vaud, Geneva, the Three Lakes, German-speaking Switzerland and Ticino.
  - Vaud: Lavaux, with the grands crus Dézaley and Calamin; La Côte; Chablais.
  - Graubünden: the Bündner Herrschaft (Fläsch, Maienfeld, Jenins, Malans) for Pinot Noir.
- **Levels:** CMS: the regions, Lavaux; Atlas and pack: the Bündner Herrschaft (the Spätburgunder comparisons, tree §9).

### 3.5 United States (task G13)

**Register:** 27 CFR part 9. **Geometry:** the UC Davis AVA Digitizing Project (CC0).

#### Napa Valley: 17 nested AVAs

- **The list:** Atlas Peak, Calistoga, Chiles Valley, Coombsville, Crystal Springs of Napa Valley (2024), Diamond Mountain District, Howell Mountain, Los Carneros (shared with Sonoma), Mount Veeder, Oak Knoll District of Napa Valley, Oakville, Rutherford, Spring Mountain District, St. Helena, Stags Leap District, Wild Horse Valley (shared with Solano), Yountville.
- **Features:**
  - the valley floor, north to south: Calistoga, St. Helena, Rutherford, Oakville, Yountville, Oak Knoll;
  - the Mayacamas Mountains to the west: Diamond Mountain, Spring Mountain, Mount Veeder;
  - the Vaca Mountains to the east: Howell Mountain, Atlas Peak, Chiles Valley;
  - San Pablo Bay's fog and wind to the south, at Carneros.
- **Levels:** L3: Napa Valley, Carneros and the valley-floor order; CMS: mountain against valley-floor AVAs; Atlas: all 17.

#### Sonoma County

- **AVAs:** Sonoma Coast and West Sonoma Coast (2022), Fort Ross-Seaview, Petaluma Gap, Russian River Valley with Green Valley of Russian River Valley, Chalk Hill, Sonoma Valley, Moon Mountain District, Sonoma Mountain, Bennett Valley, Los Carneros, Dry Creek Valley, Alexander Valley, Knights Valley, Rockpile, Fountaingrove District, Pine Mountain-Cloverdale Peak, Northern Sonoma (*to verify* the list and nesting).
- **Features:** the Pacific; the Petaluma Gap winds; the Russian River's fog.
- **Levels:** L3: Sonoma Coast, Russian River Valley, Dry Creek, Alexander Valley; CMS: Carneros, Petaluma Gap; Atlas: all.

#### Oregon: Willamette Valley, 11 nested AVAs

- **The list:** Chehalem Mountains, with Ribbon Ridge and Laurelwood District inside it; Dundee Hills; Eola-Amity Hills; Lower Long Tom; McMinnville; Mount Pisgah, Polk County, Oregon; Tualatin Hills; Van Duzer Corridor; Yamhill-Carlton.
- **Features:** the Coast Range; the Van Duzer Corridor's Pacific winds; the Dundee Hills' red volcanic Jory soil (*to verify*).
- **Levels:** L3: Willamette Valley; CMS: Dundee Hills, Eola-Amity Hills; Atlas: all 11.

#### Central Coast and Washington

- **Central Coast:**
  - Santa Ynez Valley, with Sta. Rita Hills, Ballard Canyon, Los Olivos District and Happy Canyon of Santa Barbara; Santa Maria Valley;
  - Santa Lucia Highlands in Monterey;
  - Paso Robles and its 11 districts, established in 2014 (*to verify*).
- **Washington:** Columbia Valley, containing Yakima Valley, which contains Red Mountain; Walla Walla Valley (shared with Oregon); Horse Heaven Hills; Wahluke Slope. The Cascades' rain shadow (*to verify* the list).
- **Levels:** L3: Sta. Rita Hills, Santa Lucia Highlands, Columbia Valley, Walla Walla; Atlas: the rest.

### 3.6 Southern Hemisphere (task G13)

**Registers:**
- Australia: Wine Australia's GI register;
- New Zealand: the IPONZ GI register;
- South Africa: the Wine of Origin scheme;
- Argentina: the INV's GIs;
- Chile: the DO decree and its 2011 additions.

**Geometry:** open national sources, researched by G13 (L-25); points otherwise.

#### Australia: zones → regions → subregions (*to verify*)

- **Barossa zone:** Barossa Valley; Eden Valley, with the High Eden subregion.
- **Mount Lofty Ranges zone:** Clare Valley; Adelaide Hills, with the Lenswood and Piccadilly Valley subregions.
- **Fleurieu zone:** McLaren Vale.
- **Limestone Coast zone:** Coonawarra, with its terra rossa over limestone.
- **Port Phillip zone:** Yarra Valley, Mornington Peninsula.
- **Hunter Valley zone:** the Hunter, with Pokolbin and the Upper Hunter.
- **Western Australia:** Margaret River; Great Southern and its subregions.
- **Tasmania.**
- **Levels:** L3: Barossa and Eden, Clare, McLaren Vale, Coonawarra, Yarra, Hunter, Margaret River, Tasmania; CMS: subregions; Atlas: all.

#### New Zealand

- **Registered GIs** include Marlborough, Central Otago, Hawke's Bay, Wairarapa, Martinborough, Gisborne, Nelson, North Canterbury and Waipara Valley (*to verify* against the register).
- **Bannockburn** has been registered since 1 February 2022, inside Central Otago [IPONZ].
- **Informal sub-regions** (`informal_area`): Central Otago's Gibbston, Cromwell Basin (with Lowburn, Pisa and Bendigo), Alexandra and Wanaka; Marlborough's Wairau Valley, Awatere Valley and Southern Valleys.
- **Levels:** L3: Marlborough, Central Otago, Hawke's Bay, Martinborough; CMS: Marlborough's valleys, Bannockburn; Atlas: all.

#### South Africa: geographical unit → region → district → ward (*to verify*)

- **Coastal Region:** the Stellenbosch district and its wards: Banghoek, Bottelary, Devon Valley, Jonkershoek Valley, Papegaaiberg, Polkadraai Hills, Simonsberg-Stellenbosch, Vlottenburg.
- **Also in the Coastal Region:** Paarl, Swartland, and Constantia (a ward).
- **Cape South Coast:** the Walker Bay district, with Hemel-en-Aarde Valley, Upper Hemel-en-Aarde Valley and Hemel-en-Aarde Ridge; Elgin.
- **Levels:** L3: Stellenbosch, Paarl, Swartland, Constantia, Walker Bay, Elgin; CMS: the Hemel-en-Aarde wards; Atlas: Stellenbosch's wards.

#### Argentina (*to verify*)

- **Mendoza:** Luján de Cuyo and Maipú; the Uco Valley departments Tupungato, Tunuyán and San Carlos, with GIs such as Gualtallary, Los Chacayes, Paraje Altamira, San Pablo and Pampa El Cepillo.
- **Salta:** the Calchaquí Valleys (Cafayate).
- **Patagonia:** Neuquén, Río Negro.
- **Features:** the Andes; altitude.
- **Levels:** L3: Mendoza, Uco Valley, Luján de Cuyo, Salta, Patagonia; Atlas: the Uco GIs.

#### Chile (*to verify*)

- **DO regions and valleys:**
  - Coquimbo: Elqui, Limarí, Choapa;
  - Aconcagua: Aconcagua, Casablanca, San Antonio (with Leyda);
  - Central Valley: Maipo; Rapel (Cachapoal and Colchagua); Curicó; Maule;
  - Southern: Itata, Bío Bío, Malleco.
- **East–west designations** (2011): Costa, Entre Cordilleras, Andes.
- **Features:** the Humboldt Current, the Coastal Range, the Andes.
- **Levels:** L3: Casablanca, San Antonio, Maipo, Colchagua, Maule, the east–west designations; Atlas: the rest.
- **Signature drill:** the Costa, Entre Cordilleras and Andes band for a valley.

---

## 4. Tasks

The backlog tasks, with full acceptance criteria in [backlog.md](../backlog.md) §5:

| Task | Scope | After |
|---|---|---|
| **G10** | France (§3.1) | C2, G5, G8 |
| **G11** | Italy, Spain and Portugal (§3.2–§3.3) | C3, G5, G8 |
| **G12** | Germany, Austria and Switzerland (§3.4), with the Spätburgunder pack's sites | C6, G4 |
| **G13** | United States and the Southern Hemisphere (§3.5–§3.6) | C4, G5, G8 |

**What an atlas task owns (GEO-18):**

- the sub-region nodes that are still missing, and every `informal_area`;
- their location items;
- `BORDERS`, and `LIES_ALONG` or `ON_LANDFORM` at sub-region scale;
- the completeness assertions for its sets;
- the country's geometry layers.

**What it does not own:** content tasks keep the wine facts, and each node's location item is written by the task that creates the node. An atlas task never edits another task's dataset file.
