# Operacija „Laisva vieta“

Naršyklinis pirmo asmens žaidimas apie biuro parkingą. Vienas failas `index.html` (three.js r128 iš cdnjs, be build žingsnio).

## Kas yra aplanke
- `index.html` – visas žaidimas (HTML + CSS + JS viename faile).
- `supabase/schema.sql` – visa rezultatų lentelės schema (jau pritaikyta projekte, failas skirtas atkūrimui).
- `deploy.bat` – sukuria viešą GitHub repo `laisva-vieta`, įkelia kodą ir įjungia GitHub Pages.

## Paskelbimas
Reikia, kad Teams'e pasidalinta nuoroda atsidarytų naršyklėje, todėl žaidimas talpinamas GitHub Pages:

    deploy.bat

arba rankiniu būdu: `git init -b main`, commit, `gh repo create laisva-vieta --public --source . --push`,
tada `gh api -X POST repos/<login>/laisva-vieta/pages -f "source[branch]=main" -f "source[path]=/"`.
Adresas bus `https://<login>.github.io/laisva-vieta/` (pirmas paskelbimas užtrunka 1–2 min.).
Repo turi būti viešas – nemokamame plane Pages su privačiu repo neveikia.

## Rezultatų saugojimas
`index.html` viršuje, skiltyje `BACKEND / AUTH`, yra `const SUPA={url,key}`. Naudojama pirma veikianti vieta:
1. Supabase (projektas `laisva-vieta`, ref `ymffiqwouoglefvvzfru`, eu-central-1) – per RPC funkcijas
   `lv_register`, `lv_login`, `lv_resume`, `lv_start`, `lv_finish`, `lv_board`.
2. Claude artifact duomenų bazė – tik kai puslapis atidarytas per claude.ai.
3. `localStorage` – jei nepasiekiama niekas kita.

Faile esantis raktas yra viešas „anon“ raktas; jis gali kviesti tik tas šešias funkcijas. Lentelės `lv_players` ir
`lv_runs` turi RLS be taisyklių, tad tiesiogiai nepasiekiamos.

Apsaugos: slaptažodžiai hash'uojami serveryje (bcrypt); 5 neteisingi bandymai užrakina vardą 10 min. (išskyrus
įrenginį, kuris jau buvo prisijungęs); rezultatas priimamas tik su vienkartiniu misijos bilietu (`lv_start` →
`lv_finish`), ne greičiau kaip po 15 s ir neviršijant misijos lubų.

## Admin
Agentas su `lv_players.is_admin = true` (dabar – `admin`; slaptažodis čia nesaugomas):
- mato visas 6 misijas iškart ir nerodomas lentelėje „Geriausi agentai“;
- meniu nuoroda „Admin“ atidaro sąrašą su mygtukais „Atrakinti“ (nuima 10 min. užraktą) ir „Naujas slaptažodis“
  (pakeičia slaptažodį ir atjungia agentą visuose įrenginiuose).

Serveryje tai daro `lv_admin_list` ir `lv_admin_unlock`; abi kiekvieną kartą tikrina admin požymį pagal vardą ir token.
Kito admino atrakinti ar pakeisti negalima. Naują adminą skirti tik SQL:
`update lv_players set is_admin = true where name_lower = '<vardas>';`

## Patikrinta (2026-11-17, iš naršyklės per GitHub Pages)
- Registracija (`lv_register`), sesijos atkūrimas perkrovus puslapį (`lv_resume`) ir prisijungimas (`lv_login`).
- 1 misija: `lv_start` grąžina bilietą, `lv_finish` po >15 s priima rezultatą, jis atsiranda lentelėje
  „Geriausi agentai“ (`lv_board`) ir agento rekorduose.
- Atmetama: finišas greičiau nei po 15 s, tas pats bilietas antrą kartą, svetimas token, neegzistuojanti misija.
- Užrakinimas: po 5 klaidingų slaptažodžių svetimas įrenginys gauna `locked`; jau prisijungęs įrenginys
  prisijungia ir užraktą nuima.
- Nepatikrinta: pats žaidimas pele ir klaviatūra (testo metu tikslai įvykdyti žaidimo funkcijomis, misija
  baigta tikru E klavišu prie durų).

## Žinomos spragos
- Taškai skaičiuojami naršyklėje, tad maksimalų įmanomą rezultatą vis dar galima suklastoti.
- Žaidimas skirtas kompiuteriui (klaviatūra + pelė); telefone neveikia.
- Parkingo išplanavimas apytikslis – pastatas pagal vieną nuotrauką iš drono.

## Kodo struktūra (`index.html`, skiltys pažymėtos `/* ===== ... ===== */`)
RENDERER / SCENE → WORLD (pastatas, aikštelė, žibintai) → VEHICLES (`makeCar`, `makeRig`, `buildVehicles`) →
AUDIO (efektai ir muzika) → PARTICLES → DAMAGE / SCORE → PLAYER → TOOLS → GUARDS → MISSIONS (`MISSIONS` masyvas) →
MINIMAP → INPUT → BACKEND / AUTH → SCREENS → LOOP.
