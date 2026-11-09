# Science exam-prep app (5th grade, Hebrew)

Single-file app: `index.html`. Live site: https://denizvek.github.io/science-exam-prep/
A copy is also published as a Claude artifact: https://claude.ai/artifact/DpNcqm6Bx3hXWG96hd3n1u

## Shared results table (Supabase)
- Database setup is in `supabase.sql` (table `results`, view `results_public`, function `save_result`). The anon key may only call the function and read the view.
- `index.html` constants `SUPA_URL` / `SUPA_KEY` turn the live table on; empty means off. Project: `science-exam-prep` (ref `feoomirbcgyypvueaonc`, eu-central-1), set up and connected.
- Build: the source of truth is the artifact file; `index.html` is the same page wrapped as a full document.
- Live duels: `supabase-duels.sql` (tables `duels`, `duel_key`; functions `duel_*`). `duel_key` must match the question bank in `index.html` (qid = question id, answer = right option text); regenerate it when questions change. Each row has `course` (grade:subject, e.g. `ה:science`, `ו:science`); grade-6 qids start at 1000.

## Grades / courses
- `COURSES[grade][subject]` in `index.html` holds each course (worlds, cards, question banks); the active profile's grade (first letter of `cls`) picks it at load, switching to a profile of another grade reloads the page.
- Grade ה = metals/rocks/salts; grade ו = chapter "האנרגיה שסביבנו". Progress for grade ה science stays under `p:<id>`; other courses use `p:<id>:<grade>:<subject>`.
- Tables, "learning now" and the duel room show only the same grade; `duel_invite` refuses other grades.

## Rules the owner set
- Final exam opens only at 100% learning meter.
- Practice: a topic is done only when every question was answered right on the first try (3 rounds per topic).
- Wrong practice answers never reveal the answer; they link to the lesson and return to the question.
- Results table shows all classes. No admin screen.
