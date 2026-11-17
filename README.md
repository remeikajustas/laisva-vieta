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

## Žinomos spragos ir nepatikrinti dalykai
- `lv_start` / `lv_finish` ir įrenginio išimtis `lv_login` funkcijoje pritaikyti, bet dar NEPATIKRINTI nei SQL lygiu,
  nei iš naršyklės. Pirmas dalykas, kurį verta padaryti: užsiregistruoti, įvykdyti 1 misiją ir pažiūrėti,
  ar rezultatas atsiranda lentelėje „Geriausi agentai“.
- Taškai skaičiuojami naršyklėje, tad maksimalų įmanomą rezultatą vis dar galima suklastoti.
- Žaidimas skirtas kompiuteriui (klaviatūra + pelė); telefone neveikia.
- Parkingo išplanavimas apytikslis – pastatas pagal vieną nuotrauką iš drono.

## Kodo struktūra (`index.html`, skiltys pažymėtos `/* ===== ... ===== */`)
RENDERER / SCENE → WORLD (pastatas, aikštelė, žibintai) → VEHICLES (`makeCar`, `makeRig`, `buildVehicles`) →
AUDIO (efektai ir muzika) → PARTICLES → DAMAGE / SCORE → PLAYER → TOOLS → GUARDS → MISSIONS (`MISSIONS` masyvas) →
MINIMAP → INPUT → BACKEND / AUTH → SCREENS → LOOP.
