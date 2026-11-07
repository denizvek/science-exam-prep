# Science exam-prep app (5th grade, Hebrew)

Single-file app: `index.html`. Live site: https://denizvek.github.io/science-exam-prep/
A copy is also published as a Claude artifact: https://claude.ai/artifact/DpNcqm6Bx3hXWG96hd3n1u

## Next task: make the results table fill automatically with Supabase
The owner connected the Supabase connector. Steps:
1. Create (or reuse) a free Supabase project.
2. Create table `results`: id text primary key, name text, cls text, av text, meter int, lessons int, best int null, attempts int, updated timestamptz default now().
3. Row-level security: anyone (anon) may SELECT name, cls, av, meter, best, attempts, updated; anon may INSERT/UPDATE (upsert by id). Never expose deletes.
4. In `index.html`, the sync code currently posts to a Google Apps Script (`SCRIPT_URL`, `sendSync`, `loadLive`). Replace it with Supabase REST calls:
   - upsert: POST `{url}/rest/v1/results` with headers apikey, Authorization: Bearer anon, Prefer: resolution=merge-duplicates
   - read: GET `{url}/rest/v1/results?select=name,cls,av,meter,best,attempts,updated`
   Payload comes from `payload()` (id, name, cls, av, meter, lessons, best, attempts).
5. Delete `google-apps-script.gs`, test, commit and push.

## Rules the owner set
- Final exam opens only at 100% learning meter.
- Practice: a topic is done only when every question was answered right on the first try (3 rounds per topic).
- Wrong practice answers never reveal the answer; they link to the lesson and return to the question.
- Results table shows all classes. No admin screen.
