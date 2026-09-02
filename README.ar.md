<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Assets/GitGatto-AppIcon-Dark.svg">
    <img src="Assets/GitGatto-AppIcon.svg" width="120" height="120" alt="GitGatto">
  </picture>
</p>

<h1 align="center">GitGatto</h1>

<p align="center">عميل Git أصلي لنظام macOS تدعمه أدوات Agent.</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <a href="https://github.com/Lincb522/GitGatto/releases/latest"><img alt="أحدث إصدار" src="https://img.shields.io/github/v/release/Lincb522/GitGatto?display_name=tag&style=flat-square&color=E85D24"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2328?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon وIntel" src="https://img.shields.io/badge/arch-Apple_Silicon_%2B_Intel-555555?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="ترخيص MIT" src="https://img.shields.io/badge/license-MIT-2DA44E?style=flat-square"></a>
</p>

<p align="center"><a href="https://gatto.zijiu522.cn">الموقع</a> · <a href="https://github.com/Lincb522/GitGatto/releases/latest">التنزيل</a> · <a href="CHANGELOG.md">سجل الإصدارات</a> · <a href="https://github.com/Lincb522/GitGatto/issues">Issues</a></p>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/media/github-project.png" alt="مشروع GitHub"><br><sub><b>مشروع GitHub</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/workspace.png" alt="شجرة العمل والفروقات"><br><sub><b>شجرة العمل والفروقات</b></sub></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="docs/media/recovery-center.png" alt="مركز الاستعادة"><br><sub><b>مركز الاستعادة</b></sub></td>
    <td width="50%" align="center"><img src="docs/media/file-time-machine.png" alt="آلة الزمن للملفات"><br><sub><b>آلة الزمن للملفات</b></sub></td>
  </tr>
</table>

GitGatto عميل أصلي لـ Git وGitHub على macOS. يقرأ حالة المستودع من Git المثبت في النظام، وينفذ العمليات البعيدة عبر GitHub CLI، ويستخدم Agents أدوات CLI المثبتة والمسجل الدخول إليها على الـ Mac. يجمع التطبيق حالاتها وخطواتها ونتائجها في شاشة مشروع واحدة.

## لماذا صنعنا GitGatto

تمر عملية التسليم الكاملة غالبًا بين الطرفية والمحرر وGitHub وActions وصفحة الإصدار. إذا فشلت خطوة، يجب التحقق من الفرع والملفات المرحّلة وسجلات التشغيل والملفات الناتجة من جديد. ومع Agent يجب أيضًا التأكد من مجلد العمل والصلاحيات وأن السياق يخص المستودع الحالي.

بدأ GitGatto من هذه المشكلات اليومية. يبقي Git الحقيقي والأدوات الموجودة كما هي، ثم يربط عمليات المستودع والتعاون على GitHub وعمل Agents وأدلة الفشل في مسار يمكن فحصه وإيقافه ومتابعته.

## الميزات المميزة

### أهداف المشروع

تفحص مهام «تسليم التغييرات الحالية» و«التسليم عبر GitHub» و«الإصدار الكامل» الملفات المرحّلة وعمليات commit وPush وPull Request وReviews وActions والملفات الناتجة وRelease وDMG وAppcast ونسخة التطبيق المثبتة وفق ترتيب الاعتماد. يمكن أيضًا وصف النتيجة بلغة طبيعية ومراجعة الشروط الناتجة قبل التنفيذ.

تقرأ كل خطوة الحالة الفعلية من Git أو GitHub أو الـ Mac. تبقى الخطوات المكتملة بعد الانقطاع، ويمكن إرسال فشل Actions إلى Agent مع أدلته. الدمج ونشر tag وتثبيت الإصدار تحتاج إلى تأكيدات منفصلة.

### تتبع الانحدارات

يشغّل `git bisect` داخل worktree معزول من دون تبديل مساحة العمل الحالية. ينفذ الوضع التلقائي أمر تحقق محددًا، بينما يصنف الوضع اليدوي كل commit مرشح على أنه سليم أو معطوب أو متجاوز. تُحفظ commits المرشحة ورموز الخروج والمدة والمخرجات. بعد تحديد أول commit معطوب يمكن لـ Agent إعداد الإصلاح وإعادة التحقق وإنشاء Pull Request.

### التعافي من فقدان العمل

يراقب مركز الاستعادة المستودعات المحلية المضافة إلى GitGatto. يحفظ العمل غير الملتزم به وفق جدول، وينشئ نقطة استعادة عند بلوغ حد الملفات أو الأسطر، ويدعم النسخ اليدوي. لا يعيد كتابة المحتوى إذا لم يتغير.

تحتوي نقطة الاستعادة على Git bundle للمستودع ونسخ من الملفات غير الملتزم بها. يحتفظ كل مستودع بثلاث نقاط دورية كحد أقصى. يمكن عرض المساحة المستخدمة وفتح مجلدات النسخ وحذف نقطة واحدة أو جميع نسخ مستودع واستعادة النقطة في نسخة جديدة من المستودع. عند تغيير الموقع ينقل GitGatto البيانات الموجودة ويتحقق منها قبل اعتماد الوجهة الجديدة.

### Agents مخصصة لمهام Git

يدعم GitGatto كلًا من Codex CLI وClaude Code وGemini CLI وOpenCode وقوالب CLI المخصصة. تستخدم عمليات المستودع والترجمة وتثبيت البرامج قنوات تنفيذ منفصلة، لذلك لا تمنع مهمة طويلة ترجمة المستندات.

يمكن لـ Agent استخدام المخرجات الكاملة للخطأ لمعالجة مشكلات Git وGit LFS وhooks والتوقيع والفروع والمزامنة والتعارضات وPull Requests وActions. إذا كانت منطقة staging فارغة، يمكن إنشاء رسالة commit بعد ترحيل التغييرات الحالية أولًا، ثم تنفيذ commit أو commit وPush. يُعرض README المعاد تحريره كاملًا قبل أن يسجل زر «تطبيق commit» ذلك المستند وحده.

## Git وGitHub

- إدارة شجرة العمل وstaging وcommits وPull وPush والفروع وstashes وworktrees.
- عرض Diff سطرًا بسطر ومخطط commits وBlame وسجل الملف والصور وSVG والفيديو من المراجعات السابقة.
- تحرير نتائج تعارضات merge وrebase وstash ثم المتابعة أو التجاوز أو الإلغاء.
- تحميل المستودعات المتاحة لحساب GitHub الحالي والبحث عن المستودعات والمطورين بالبحث التقريبي واللغة الطبيعية وتحميل صفحات إضافية.
- قراءة الشفرة وREADME وPull Requests وActions وReleases ومرفقات الإصدار داخل التطبيق.
- مراجعة ملفات Pull Request ووضع علامة تمت المشاهدة وتعليقات الأسطر والردود وReviews وإعادة تشغيل Actions أو إلغائها وتنزيل الملفات الناتجة.
- Star وFork وClone. يبدأ فحص الجهاز يدويًا ويسمح باختيار ما يضاف بدل استيراد القرص كاملًا.

## المستندات والترجمة والمعاينة

- عرض Markdown والصور ذات المسارات النسبية والروابط الداخلية داخل GitGatto.
- اكتشاف لغة المستند والترجمة عبر قناة Agent مستقلة؛ تُحفظ الترجمة محليًا لكل نسخة من المصدر.
- معاينة الشفرة والصور ومصدر SVG والوسائط من مساحة العمل وسجل commits وسجل الملفات.
- يعيد Agent الخاص بـ README بناء المستند اعتمادًا على ملفات المستودع واعتماداته ومواده الموجودة بدل تغيير الكلمات فقط.

## دليل التطبيقات وأدوات التطوير

- البحث عن تطبيقات قابلة للتثبيت من GitHub Releases مع الأيقونة والوصف ولقطات الشاشة والنسخة والحزم الفعلية. يستخدم DMG وZIP المثبت المحلي، وتتولى أداة Agent الصيغ الأخرى.
- اكتشاف النسخ المثبتة والتحديثات المتاحة لـ 99 بيئة تشغيل وأداة بناء وحاوية وأداة سحابية وقاعدة بيانات وأداة CLI.
- تنفيذ التثبيت والترقية عبر ثلاثة مسارات متوازية مع التحديد المتعدد والترقية الجماعية. تُنفذ تغييرات Homebrew في طابور تسلسلي مستقل لمنع الكتابة المتزامنة إلى Cellar.
- بعد التثبيت يكمل Agent إعداد PATH للمستخدم وتسجيل المكونات والتهيئة وترحيل الإعدادات، ثم يعيد التحقق من الملف التنفيذي والنسخة.
- الاحتفاظ بتقدم المراحل والمخرجات الأصلية وشروح مترجمة للأخطاء المعروفة أثناء التنزيل والتثبيت والإعداد والتحقق.

## مستندات المشروع

- [خريطة الطريق](docs/ROADMAP.md): المراحل المنفذة والعمل المخطط والحدود.
- [البنية](docs/ARCHITECTURE.md): ملكية الحالة وحدود الخدمات ومسارات البيانات الأساسية.
- [Star History](https://www.star-history.com/#Lincb522/GitGatto&Date): نمو نجوم GitHub بمرور الوقت.

![GitGatto roadmap](docs/media/roadmap.svg)

![GitGatto architecture](docs/media/architecture-overview.svg)

[![GitGatto Star History](docs/media/star-history.svg)](https://www.star-history.com/#Lincb522/GitGatto&Date)

## التثبيت

نزّل DMG من [Releases](https://github.com/Lincb522/GitGatto/releases/latest) واسحب GitGatto إلى مجلد Applications. الإصدارات ملفات Universal لكل من Apple Silicon وIntel وتتطلب macOS 14 أو أحدث.

| الميزة | المتطلب |
| --- | --- |
| المستودعات المحلية | Git |
| مستودعات GitHub وPR وActions والعمليات البعيدة | [GitHub CLI](https://cli.github.com/) مسجل الدخول |
| مسارات Agent | أداة CLI واحدة مدعومة ومثبتة ومسجل الدخول إليها على الأقل |
| فحص تحديثات Homebrew | Homebrew |

تأتي تحديثات التطبيق وملاحظات الإصدار وحزم التثبيت من GitHub Releases لهذا المستودع.

## البيانات المحلية والصلاحيات

- تبقى الإعدادات وقائمة المستودعات وأهداف المشاريع وتحقيقات الانحدار ومحادثات وسجلات Agents والتنزيلات والترجمات على الـ Mac.
- عند تفعيل حماية المستودع، تُحفظ Git bundles ونسخ الملفات غير الملتزم بها في Application Support أو في الموقع الذي تختاره. يحتفظ كل مستودع بثلاث نسخ كحد أقصى ويمكن حذفها من مركز الاستعادة.
- يستمر Git وSSH وGitHub CLI وأدوات Agent في استخدام مخازن بيانات الاعتماد الخاصة بها. لا يحفظ GitGatto رموز الوصول أو كلمات المرور أو المفاتيح الخاصة.
- لا تعمل Pull وPush وFork والتعليقات وReviews وActions وتثبيت التطبيقات وتغييرات أدوات التطوير إلا بعد إجراء صريح داخل التطبيق.

## التطوير

يتطلب التطوير macOS 14 أو أحدث وسلسلة أدوات Swift المحددة في المشروع.

```bash
git clone https://github.com/Lincb522/GitGatto.git
cd GitGatto
swift package resolve
swift test
open GitGatto.xcodeproj
```

يستخدم المشروع Swift 6 وSwiftUI وAppKit وWebKit وAVKit، ويستخدم Alamofire 5.12 للشبكة وSparkle 2.9.6 للتحديث. راجع [CONTRIBUTING.md](CONTRIBUTING.md) لقواعد المساهمة و[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) لحدود النظام.

## شكر وتقدير

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Alamofire](https://github.com/Alamofire/Alamofire)
- [SwiftUI-Animations](https://github.com/Shubham0812/SwiftUI-Animations)
- [GitHub CLI](https://github.com/cli/cli)
- [Simple Icons](https://github.com/simple-icons/simple-icons) و[VSCode Icons](https://github.com/vscode-icons/vscode-icons) و[Devicon](https://github.com/devicons/devicon) و[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)

الإصدارات والتراخيص الدقيقة موجودة في [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). أبلغ عن مشكلات الأمان عبر القناة الموضحة في [SECURITY.md](SECURITY.md).

## الترخيص

يطور **ZIJIU522** تطبيق GitGatto وينشره بموجب [ترخيص MIT](LICENSE).
