# Science exam-prep app (5th grade, Hebrew)

Single-file app: `index.html`. Live site: https://denizvek.github.io/science-exam-prep/
A copy is also published as a Claude artifact: https://claude.ai/artifact/DpNcqm6Bx3hXWG96hd3n1u

## Shared results table (Supabase)
- Database setup is in `supabase.sql` (table `results`, view `results_public`, function `save_result`). The anon key may only call the function and read the view.
- `index.html` constants `SUPA_URL` / `SUPA_KEY` turn the live table on; empty means off. Project: `science-exam-prep` (ref `feoomirbcgyypvueaonc`, eu-central-1), set up and connected.
- Build: the source of truth is the artifact file; `index.html` is the same page wrapped as a full document.
- Live duels: `supabase-duels.sql` (tables `duels`, `duel_key`; functions `duel_*`). `duel_key` must match the question bank in `index.html` (qid = question id, answer = right option text); regenerate it when questions change.

## Rules the owner set
- Final exam opens only at 100% learning meter.
- Practice: a topic is done only when every question was answered right on the first try (3 rounds per topic).
- Wrong practice answers never reveal the answer; they link to the lesson and return to the question.
- Results table shows all classes. No admin screen.
