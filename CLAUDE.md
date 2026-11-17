# Science exam-prep app (5th grade, Hebrew)

Single-file app: `index.html`. Live site: https://denizvek.github.io/science-exam-prep/
A copy is also published as a Claude artifact: https://claude.ai/artifact/DpNcqm6Bx3hXWG96hd3n1u

## Shared results table (Supabase)
- Database setup is in `supabase.sql` (table `results`, view `results_public`, function `save_result`). The anon key may only call the function and read the view.
- `index.html` constants `SUPA_URL` / `SUPA_KEY` turn the live table on; empty means off. Project: `science-exam-prep` (ref `feoomirbcgyypvueaonc`, eu-central-1), set up and connected.
- Build: the source of truth is the artifact file; `index.html` is the same page wrapped as a full document.
- Live duels: `supabase-duels.sql` (tables `duels`, `duel_key`; functions `duel_*`). `duel_key` must match the question bank in `index.html` (qid = question id, answer = right option text); regenerate it when questions change. Each row has `course` (grade:subject, e.g. `ה:science`, `ו:science`); grade-6 qids start at 1000, grade-2 at 2000 (questions with a passage, `ctx`, are not in duel_key).

## Grades / courses
- `COURSES[grade][subject]` in `index.html` holds each course (worlds, cards, question banks); the active profile's grade (first letter of `cls`) picks it at load, switching to a profile of another grade reloads the page.
- Grade ב = preparation for the gifted screening test, stage A (`COURSES.ב.gifted`: reading comprehension with passages in `PASSAGES_G2`, math, word problems, sequences; original questions; never name any commercial prep course as a source). Grade ה = metals/rocks/salts; grade ו = chapter "האנרגיה שסביבנו". Progress for grade ה science stays under `p:<id>`; other courses use `p:<id>:<grade>:<subject>`.
- Grade ו has two subjects: `science` and `english` (Unit 1: 78 words, to be, have/has, Present Simple s/es/ies, capital letters, reading; original sentences and passages). A grade with several subjects asks "מה לומדים היום?" once per visit (`sessionStorage.subjPicked`); the choice is kept per profile in `sci1:subj`, and a dropdown on the home page switches it.
- Each subject has its own server row: `SID()` = `<id>` for the grade's first subject, `<id>~english` for others. `results_public.subject` tells them apart; tables, podium, "learning now" and duels show only the same grade and subject. English duel_key rows: course `ו:english`, qids 3000+.
- Tables, "learning now" and the duel room show only the same grade (and subject); `duel_invite` refuses other grades or subjects.

## Rules the owner set
- Final exam opens only at 100% learning meter.
- Practice: a topic is done only when every question was answered right on the first try (3 rounds per topic).
- Wrong practice answers never reveal the answer; they link to the lesson and return to the question.
- Results table shows all classes of the child's own grade. No admin screen.
- Duels only for children whose learning meter is 100%; before that, one trial duel (`P.duelTry`), then a popup asks them to finish the material.
- Any child may look at and study another grade's material (`sci1:view`), but nothing is sent: no scores, not in tables, no duels.
- New school year (1 September): progress resets on the device (`P.season`), kids re-confirm their class; the view `results_public` shows only rows active since `season_start()` and counts duel wins from this school year only.
