# Client feedback list — September 2026

The client's own notes, sent with screenshots. The Arabic original is kept under
each item so nothing is lost in translation. Status is filled in only from
verified code with `file:line` evidence, never assumed.

Status values: **DONE** (shipped, evidence cited) · **OPEN** (not in the code) ·
**PARTIAL** (some of it shipped) · **UNVERIFIED** (not yet audited).

The client reports that another agent worked this list during the week of
2026-09-14, so several items may already be done. Every entry is therefore to be
re-checked against the code before it is called done.

---

## A. Notifications

### A1 — Dashboard-only notifications must never reach a member's phone
Only staff should see them. A beneficiary, donor, volunteer, guest or marriage
user must not receive notifications meant for the dashboard.

> كثير من الاشعارات تصل للتطبيق ولكن هذه الاشعارات يجب ان لا تصل للهاتف فهذه اشعارات خاصة بالداشبورد ولا يجب ان يطلع عليها المستخدم ان كان متعفف او متبرع او متطورع او زائر او خاطب فقط الموظف

**Status: UNVERIFIED**

### A2 — Tapping a notification must open what it is about
A sponsorship or message notification must open that sponsorship or that
conversation, not the notifications list.

> عند وصول اشعار للهاتف والضغط عليه يفتح التطبيق لكن تفتح الواجهة الخاصة بالاشعار ... مثلا وصل اشعار كفالة او اشعار رسالة لا تفتح واجهة الرسالة او واجهة الكفالة

**Status: DONE** — PR #145; verified on device 2026-09-16 (tapping a marriage
chat push opened that chat).

### A3 — A sponsorship approval must name the project
"Your sponsorship for the project was accepted" must say *which* project.

> عند تقديم كفالة ويتم الموافقة عليها يكون الاشعار كالتالي ( تم قبول كفالتك للمشروع ) ويجب ان يظهر اسم المشروع

**Status: UNVERIFIED**

### A4 — A new account must notify the dashboard
Registering a new account produced no dashboard notification; the dashboard
showed the account as active with no approval notification.

> قمنا بتسجيل حساب جديد لكن لم يصل اشعار للداشبورد / وما يظهر في الداشبورد انه نشط ولكن لا يظهر اشعار للموافقة

**Status: UNVERIFIED**

### A5 — Sidebar badge counts never clear
Contributions shows 1, Market 5, and marriage / support / follow-up also carry
numbers that stay after everything has been opened. Unfinished task or bug?

> في قسم المساهمات يوجد اشعار رقم 1 ... ايضا السوق يحتوي على 5 اشعارات وجميعها تم الضغط عليها لكن ما سبب بقاء رقم الاشعار ... باختصار الرقم الذي يظهر امام الاقسام بشكل عام هل هو مهمه لم تكمل او خلل برمجي !

**Status: UNVERIFIED**

---

## B. Registration, accounts and identity

### B1 — Phone number length
Registration accepted a 10-digit number. Iraqi numbers are 11 digits. Accept 11
digits, or a valid number; international numbers per their own country's rule.

> اثناء التسجيل تم قبول رقم هاتف يتكون من 10 خانات ! بينما الارقام الهواتف ١١ رقم الرجاء معالجة هذا الادخال بحيث يكون اما يقبل ١١ رقم او رقم صحيح ، عدا الارقام الدولية تقبل حسب وضعها ودولتها

**Status: UNVERIFIED**

### B2 — One account per phone number, enforced by the database

> الرجاء اجبار قاعدة البيانات ان يكون لكل رقم هاتف حساب واحد فقط ويمكن التكرار اي لا يمكن التسجيل حسابين برقم هاتف واحد

**Status: UNVERIFIED**

### B3 — "Staff sign-in is not available yet. Ask the administrator for your code"
What does it mean? And it must be Arabic, not English.

> ماذا يقصد بهذه العبارة بتسجيل الموظفين غير متاح حاليا ؟ ايضا يفضل ان تكون باللغة العربية وليس الانكليزي

**Status: UNVERIFIED**

### B4 — "Account type" (نوع الحساب) in the profile
What is it for? It carries no detail.

> نوع الحساب ما الغرض منها ! لانها لا تحتوي على تفاصيل

**Status: UNVERIFIED**

### B5 — Profile picture chosen at registration sometimes does not display

> عند اختيار صورة اثناء التسجيل واكمال التسجيل الصورة في بعض الاحيان لا يتم عرضها او لا تظهر

**Status: UNVERIFIED**

### B6 — Profile edits sometimes do not reach the dashboard

> في بعض الاحيان عند تغيير بيانات في الملف الشخصي فانه لا يتم تغييره في الداشبورد

**Status: UNVERIFIED**

---

## C. App and dashboard layout

### C1 — The bottom section bar collides with the phone's own navigation bar

> ايضا الشريط السفلي للاقسام يحدث تداخل بينه وبين شريط خيارات الهاتف

**Status: UNVERIFIED**

### C2 — Font legibility
Letters run together — "الاسم" reads as "السسم", and elsewhere too.

> يفضل اختيار خط اكثر وضوحا فبعض الكلمات متداخله مثل كلمة الاسم هنا تظهر وكانها السسم

**Status: UNVERIFIED**

### C3 — Consistent column order across tables, and date above time
Some sections already order it well. Apply the same everywhere.

> بعض الاقسام الترتيب جيد كما موضح في الشريط الاعلى ... لكن في بعض الاقسام يفضل ان يكون بنفس الترتيب ... التاريخ في الاعلى ثم اسفله الوقت ليكون واضح دون تداخل

**Status: UNVERIFIED**

### C4 — Marriage rows in the dashboard take far too much vertical space

> في قسم الزواج يتم عرض بعض المستخدمين بهذه الطريقة اي انه ياخذ مساحة كبيرة ما السبب

**Status: UNVERIFIED**

---

## D. City guide and marketplace

### D1 — Missing neighbourhoods, and English names
Many are missing; allow adding them by hand from the dashboard. Translate the
names to Arabic.

> هناك احياء عديدة لم تتم اضافتها اذا لم تتوفر لديكم يمكنكم تفعيل خيار ان نقوم باضافتهم يدويا من الداش بورد / وايضا الاسماء بالانكليزي الرجاء الترجمه للعربي

**Status: UNVERIFIED**

### D2 — Adding an activity to the Mosul guide also adds it to Community Services

> عند اضافة نشاط في دليل الموصل لماذا يتم اضافته ايضا في خدمات المجتمع !؟

**Status: UNVERIFIED**

### D3 — Adding an activity shows "could not send" but the item appears anyway

> عند اضافة نشاط داخل المدينه يظهر تعذر الارسال لكنه يظهر في القائمه !

**Status: UNVERIFIED**

### D4 — Marketplace and guide need real categories
Posts repeat over time and older ones become unreachable. Organise them into
sections — food, handmade, and so on — the way KiCard, Amazon or Asiacell do.

> المتجر ودليل الموصل كلنا نعلم انه سيكون هناك تفاصيل متشابه او مكرره ... ان يتم ادراجهم ضمن الاقسام الخاصة بهم مثل الطعام او الاعمال اليدوية ... مثل تطبيق كي كارد ... او تطبيق امزون او تطبيق اسياسيل

**Status: UNVERIFIED**

---

## E. Sections and placement

### E1 — In-kind contributions sit under Services; they belong under Contributions

> المساهمة العينية موقعها داخل قسم الخدمات ! بينما يجب ان تكون داخل قسم المساهمات

**Status: UNVERIFIED**

### E2 — "Contact support" and "Send a support request" look like the same thing

> (التواصل مع الدعم) (و ارسال طلب دعم) الرجاء تدقيقهما فنعتقد انهما نفس الخيار لكن بمسميات مختلفة

**Status: UNVERIFIED**

### E3 — Adding a post in News & Media is broken

> هناك مشكلة عند اضافة منشور في قسم الاخبار والاعلام الرجاء التدقيق من قبلكم

**Status: UNVERIFIED**

---

## F. Marriage and engagement

### F1 — Suitor registration: where is it, and the new-profile form is incomplete

> تسجيل المستخدم / الخاطب اين نجده ... فخيار ملف جديد لا يحتوي على كل التفاصيل المطلوبة التي تم ارسالها

**Status: UNVERIFIED**

### F2 — The engagement section must be fully separated from humanitarian posts

> قسم الخطوبة هو قسم خاص بالحفلات والاعراس والمناشير ايضا ويفضل فصلها نهائيا عن مناشير الاعمال الانسانية

**Status: UNVERIFIED**

### F3 — Engagement section structure
Staff-only posts with reactions and comments; a user profile; service sections
underneath, clear and easy to reach. Services repeat — several kosha models,
several halls — so each section shows multiple options with prices.

> الواجهة هي مناشير يتم نشرها من قبل الموظف حصرا وفيها التفاعل والتعليق ... وايضا الخدمات سيكون فيها تكرار مثلا قسم الكوشات ... او قسم القاعات

**Status: UNVERIFIED**

---

## G. Chat rules

The eight rules, restated in this list and audited in full in
`docs/chat-policy-conformance-2026-09.md`.

1. No communication between donor, beneficiary and volunteer, ever.
2. No volunteer ↔ beneficiary; volunteers talk to staff, or to specific
   volunteers staff choose.
3. The donor is contacted only by staff.
4. A volunteer can contact staff for instructions.
5. Volunteer chat happens in staff-created groups (field team, training team,
   distribution team).
6. A masked group for donor + beneficiary + staff, created by staff, showing
   labels instead of real names.
7. Marriage: users never message each other; staff open a masked chat.
8. Every chat can be paused, resumed, archived, exported and deleted.

**Status: DONE** — rules 2 and 4–8 hold in code; rules 1 and 3 closed once the
legacy direct threads were retired (run by the client, 2026-09-16) and team
groups were restricted to volunteers and staff (PR #137).

---

## Where this came from

Sent by the client with screenshots, outside Claude Code, and recorded here on
2026-09-16 after it could not be found in any session transcript. Do not rely on
chat history for this list again.
