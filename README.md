# מבחן במדעים – כיתה ה׳

אפליקציית הכנה למבחן: מתכות, סלעים וקרקעות, מלחים.
האתר: https://denizvek.github.io/science-exam-prep/

## גיליון התוצאות וכניסת מנהל

ההתקדמות של כל תלמיד נשלחת אוטומטית לגיליון Google, והמנהל רואה את כולם בכתובת `#admin`.

1. יוצרים Google Sheet חדש ← Extensions ← Apps Script.
2. מוחקים את הקוד הקיים ומדביקים את התוכן של `google-apps-script.gs`.
3. Project Settings ← Script properties ← מוסיפים `ADMIN_PASSWORD` עם סיסמה.
4. Deploy ← New deployment ← Web app. Execute as: **Me**. Who has access: **Anyone**.
5. מעתיקים את ה-Web app URL ומכניסים אותו ב-`index.html` במקום `SCRIPT_URL=""`.
