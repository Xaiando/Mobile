# Irish Whiskey release-time source check — 30 September 2026

The current public EU register attachment supports the three existing CMS lessons without a demonstrated factual correction. A final Irish national amendment decision after the 4 September consultation deadline remains **unknown**. This is a bounded source-currency check, not qualified factual verification.

## Registered evidence actually observed

The [public eAmbrosia search endpoint](https://ec.europa.eu/geographical-indications-register/eambrosia-public-api/api/gi-applications/filter), queried by protected name at 10:24:00 UTC, returned one record: 16495, PGI-IE+UK(NI)-01897, Registered, version 2, with lastApprovedId 16495. Its [record detail](https://ec.europa.eu/geographical-indications-register/eambrosia-public-api/api/gi-applications/id/16495?lang=en), read at 10:24:20 UTC, links Ares(2019)5469807 and [technical attachment 55944](https://ec.europa.eu/geographical-indications-register/eambrosia-public-api/api/v1/attachments/55944). The 20-page PDF has an October 2014 cover and a 29 August 2019 receipt reference. Those dates are not a 2026 amendment approval date.

| Existing ID | Supported assertion boundary |
|---|---|
| ki_cms_irish_origin | Island of Ireland including Northern Ireland; fermented cereal mash; at least three years in wooden casks no larger than 700 litres. Printed p. 1, section 2.1.1. |
| ki_cms_irish_pot_malt | Pot Still uses malted and unmalted barley; Malt uses malted barley; the copper pot still distinction. Printed p. 1, section 2.1.2, and pp. 6–7, sections 4.2.1–4.2.2. |
| ki_cms_irish_blend | Pot Still, Malt and Grain varieties may be combined as Blended Irish Whiskey; no exact component proportions are taught. Printed pp. 1 and 8, sections 2.1.1 and 4.2.4. |

No discrepancy was found in these bounded statements or the dependent barley-comparison case. The app does not teach proposed new grain percentages.

## Consultation and unresolved outcome

Live HTML from the [DAFM GI page](https://www.gov.ie/en/department-of-agriculture-food-and-the-marine/publications/geographical-indications-spirit-drinks/) has modification metadata 24 June 2026 and still links the [October 2014 technical file](https://assets.gov.ie/static/documents/irish-whiskey-technical-file-pdf-428kb.pdf). Its older May 2025 search excerpt is stale.

The [official announcement](https://www.gov.ie/en/department-of-agriculture-food-and-the-marine/press-releases/public-consultation-on-irish-whiskey-product-specification/), published 24 June 2026, gives a consultation period of 26 June–4 September 2026 and subsequent departmental evaluation. Consultation is not approval. The announcement's [consultation link](https://www.gov.ie/en/department-of-agriculture-food-and-the-marine/consultations/public-consultation-on-proposed-amendments-to-the-irish-whiskey-technical-file/) returned HTTP 404 in the bounded direct request.

Exactly one final [targeted national outcome search](https://www.gov.ie/en/search/?q=Irish%20Whiskey%20amendment%20approval) was read at 10:31:48 UTC (HTTP 200, five results). It exposed the consultation dated 4 September, but no observed post-deadline DAFM approval/adoption notice. Neither that search nor the observed EU record proves that no national standard amendment has been approved; publication lag and the final national disposition remain unresolved. Research stopped at this bound.

At the next release source-currency gate, or when a dated national outcome/new registered attachment becomes available, make one targeted DAFM outcome lookup and compare the same EU record and attachment. Accept an actual dated approval or applicable amended specification before revising legal claims. Keep the existing facts and expert-unverified status meanwhile.

Only this note was added in the separate CMS continuation worktree. No curriculum facts, verified ledger, frozen NEXT source, SDK, Git state or CI were changed. Detailed prior observations are retained locally under ignored NEXT build/irish-whiskey-release-check-2026-09-30/evidence.json.
