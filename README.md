<h1 align="center">Flutter Quality Ratchet</h1>

<p align="center">
  Freeze today's code-quality debt in a baseline that can only go down, and fail CI on every new violation.
</p>

<p align="center">
  <a href="https://github.com/youssef336/flutter_quality_ratchet/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/youssef336/flutter_quality_ratchet/test.yml?branch=main&style=for-the-badge&label=tests" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Dart-%5E3.9-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Flutter-ready-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/GitHub%20Action-composite-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Action">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **English summary.** Flutter Quality Ratchet is a small Dart CLI (`quality_ratchet`) that lets any
> Dart or Flutter project adopt strict rules *today* without fixing the whole codebase first. You
> describe rules in `quality_ratchet.yaml` (file size, function size, forbidden imports between
> layers, forbidden code patterns such as `setState(` or `Color(0x`, and hardcoded UI strings);
> `init` counts the current violations per file and freezes them in `quality_ratchet_baseline.json`.
> From then on `check` fails on any **new** violation or any file that **grew**, and also when a
> count went **down** until you lock the progress in with `update-baseline`, which is shrink-only.
> Moving debt into a new file (a split) is allowed while a rule's total holds. With `--base <ref>`
> a **raise guard** compares the baseline with the one at the git merge-base, so a hand-edited
> baseline is visible in review; an urgent exception carries a `reason` and shows up as a warning.
> Comments and string literals are stripped before matching (interpolations stay code). Output is
> human text, GitHub annotations or JSON; exit codes are 0 clean, 1 violations, 2 usage/config
> error. Ships with a composite GitHub Action: `uses: youssef336/flutter_quality_ratchet@v1`.

<div dir="rtl">

عندك مشروع Flutter فيه مئات الـ `print` والألوان المكتوبة بإيدك والفايلات اللي عدّت الألف سطر،
وعايز تبدأ تشدّد القواعد من النهارده، من غير ما توقف الشغل شهر عشان تنضف كل حاجة؟
ده بالظبط اللي الأداة دي بتعمله.

## 🪜 الفكرة: «الـ ratchet»

الـ ratchet هو الترس اللي بيلف في اتجاه واحد بس. هنا الاتجاه ده هو **لتحت**:

- 🧊 **الدين القديم بيتجمّد**: أول مرة بتشغّل `init`، الأداة بتعدّ المخالفات في كل فايل
  وبتكتبها في `quality_ratchet_baseline.json`. ده «المسموح بيه» النهارده، ومحدش هيزعّقلك عليه.
- ⬇️ **العدد يقدر ينزل بس**: لو صلّحت حاجة قديمة، العدد بينزل. الأداة بتطلب منك تثبّت التحسين
  (`update-baseline`) عشان محدش يرجع يستخدم المساحة اللي فضيت.
- 🚫 **الكود الجديد لازم يبقى نضيف**: أي مخالفة جديدة، أو فايل قديم زادت مخالفاته، الـ check بيفشل.
- 🛡 **الـ baseline مش بيتعلّى**: `update-baseline` عمره ما بيزوّد رقم. ولو حد علّاه بإيده في
  PR، الـ raise guard بيقارن بالـ baseline اللي في الـ merge-base وبيقفش ده.

النتيجة: الكود بيتحسّن مع كل PR، من غير big-bang refactor.

## 📦 التثبيت

**عالمي (global):**

</div>

```bash
dart pub global activate --source git https://github.com/youssef336/flutter_quality_ratchet
quality_ratchet --help
```

<div dir="rtl">

**أو كـ dev_dependency جوه المشروع** (كل الفريق ياخد نفس النسخة):

</div>

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_quality_ratchet:
    git:
      url: https://github.com/youssef336/flutter_quality_ratchet
      ref: v0.1.0
```

```bash
dart run flutter_quality_ratchet check
```

<div dir="rtl">

## 🚀 أول مرة

</div>

```bash
cd my_flutter_app
quality_ratchet init        # بيكتب quality_ratchet.yaml وبيجمّد الدين الحالي
quality_ratchet check       # لازم يطلع 0
git add quality_ratchet.yaml quality_ratchet_baseline.json
```

<div dir="rtl">

`init` بيبص على `pubspec.yaml`: لو المشروع Flutter بيضيف قواعد الـ UI (النصوص المكتوبة في
`Text(...)` والألوان)، ولو Dart بس بيكتفي بالقواعد العامة. الملف كله متعلّق عليه، عدّل فيه براحتك.

## ⌨️ الأوامر

| الأمر | بيعمل إيه |
|---|---|
| `init [--force]` | بيكتب `quality_ratchet.yaml` بقيم معقولة، وبيعمل baseline بالأعداد الحالية |
| `check [--base <ref>] [--rule id] [--format text\|github\|json]` | الفحص نفسه. بيفشل لو فيه جديد، أو زيادة، أو baseline قديم (stale)، أو baseline اتعلّى |
| `update-baseline [--base <ref>] [--rule id]` | بينزّل الـ baseline للأعداد الحالية. **بينزّل بس**، عمره ما بيعلّي |
| `seed-rule <id>` | لما تضيف قاعدة جديدة: بيكتب الـ section بتاعتها بس، ومش بيلمس الباقي |
| `explain [--rule id]` | بيعرض كل قاعدة، إعداداتها، والـ baseline قدام العدد الحالي، وأكتر الفايلات |

`-C <dir>` بيشغّلها على مشروع في فولدر تاني، و `--no-color` بيقفل الألوان.

**الـ exit codes:** `0` نضيف · `1` فيه مخالفات · `2` غلط في الأمر أو الإعدادات أو الـ baseline مش موجود.

**شكل الـ output:**

</div>

```text
quality_ratchet check · 158 file(s) scanned

Errors (1)
  x lib/features/home/presentation/views/widgets/cart_item.dart:127  [no_print] `print(`: Use a logger instead of print.

  Rule                  Unit   Baseline -> Now  Status
  file_size             lines         0 -> 0    holds
  long_functions        lines       539 -> 539  holds
  no_print              count         5 -> 6    1 error(s)
  no_core_to_features   count        26 -> 26   holds
  hardcoded_ui_strings  count        10 -> 10   holds
  no_hardcoded_colors   count        69 -> 69   holds

FAILED: 1 error(s).
  Fix the reported lines. The baseline only covers old debt: new and changed code must be clean.
```

<div dir="rtl">

## ⚙️ ملف الإعدادات `quality_ratchet.yaml`

</div>

```yaml
include:                 # الافتراضي: lib/**/*.dart
  - lib/**/*.dart
exclude:                 # الافتراضي: الكود المتولّد
  - "*.g.dart"
  - "*.freezed.dart"
  - generated/
  - lib/gen/
baseline: quality_ratchet_baseline.json   # الافتراضي

rules:
  - id: file_size                # اسم من اختيارك، وهو المفتاح في الـ baseline
    type: max_file_lines
    message: Split this file.    # بيظهر مع كل مخالفة: قول للناس يعملوا إيه
    # files: [lib/**]            # (اختياري) تحدّد القاعدة على فايلات معينة
    # exempt: [lib/legacy/**]    # (اختياري) فايلات مستثناة
    fail_above: 500
```

<div dir="rtl">

**الـ globs:** `*` (من غير `/`)، `**/` (أي عدد فولدرات)، `{a,b}`، `[abc]`. الـ glob اللي
مفيهوش `/` بيطابق في أي عمق (`*.g.dart`)، واللي آخره `/` معناه «كل اللي جوه الفولدر ده» (`generated/`).

### 📏 `max_file_lines`: حجم الفايل

</div>

```yaml
- id: file_size
  type: max_file_lines
  fail_above: 500           # أكتر من كده = مخالفة، والـ baseline بيحفظ عدد السطور
  warn_above: 400           # (اختياري) تحذير بس لأي فايل أكبر من كده
  new_file_warn_above: 300  # (اختياري) تحذير للفايلات الجديدة، بيشتغل مع --base بس
  message: Split this file into smaller files.
```

<div dir="rtl">

الفايل الكبير القديم يقدر يصغر بس، عمره ما يكبر. «السطور» هي اللي الـ editor بيرقّمها
(زي `wc -l` لأي فايل آخره سطر فاضي).

### 🧩 `max_function_lines`: طول الـ function

</div>

```yaml
- id: long_functions
  type: max_function_lines
  max: 80
  message: Extract smaller functions or widgets.
```

<div dir="rtl">

بيقيس الـ functions والـ methods والـ constructors والـ getters اللي ليها اسم وجسمها `{ }`
(من سطر الاسم لحد القوس اللي بيقفل). الـ baseline بيحفظ عدد السطور، فالـ `build` الطويلة
تقدر تقصر بس.

### 🧱 `forbidden_imports`: حدود الطبقات

</div>

```yaml
- id: no_core_to_features
  type: forbidden_imports
  from: lib/core/**
  forbidden:
    - lib/features/**
    - package:get/**        # ينفع تمنع باكدج خارجية كمان
  exempt:
    - lib/core/routing/**   # الـ router لازم يشوف كل الصفحات
  message: lib/core must not import lib/features.
```

<div dir="rtl">

بيفهم الـ imports النسبية (`../features/x.dart`) و `package:<اسم مشروعك>/...` (بيقرا الاسم من
`pubspec.yaml`)، والـ exports، والـ conditional imports. الـ glob بيتطابق على المسار بعد الـ
resolve وعلى الـ URI نفسه، فـ `dart:io` و `package:get/**` شغالين.

### 🔍 `forbidden_patterns`: أنماط ممنوعة

</div>

```yaml
- id: no_set_state
  type: forbidden_patterns
  patterns:
    - '\bsetState\('
  message: Use your state management instead of setState.

- id: no_hardcoded_colors
  type: forbidden_patterns
  patterns:
    - '\bColor\(0x'
    - '\bColor\.from(ARGB|RGBO)\('
  exempt: [lib/**/theme/**]
  message: Use a color from the theme.

- id: design_system_buttons
  type: forbidden_patterns
  patterns:
    - '\b(ElevatedButton|TextButton|OutlinedButton)\('
  files: [lib/features/**]
  message: Use the shared AppButton.
```

<div dir="rtl">

الـ regex بيشتغل على **الكود بس**: التعليقات ونصوص الـ strings بتتمسح الأول، فـ
`// setState(` أو `'setState('` مش هيتحسبوا. بس اللي جوه `${...}` كود، فبيتحسب.
اكتب الـ regex بين `'...'` في الـ YAML عشان الـ `\` يفضل زي ما هو.

### 💬 `hardcoded_strings`: نصوص مكتوبة في الـ UI

</div>

```yaml
- id: hardcoded_ui_strings
  type: hardcoded_strings
  widgets: [Text, SelectableText, AutoSizeText]   # أول argument positional
  named_args: [hintText, labelText, title]        # named arguments
  ignore:
    - '^https?://'
  message: Move this text to your translation files.
```

<div dir="rtl">

بيمسك الـ string literal اللي **متباصي على طول**: `Text('Welcome')` و `hintText: 'Email'`.
ومش بيمسك `Text('key'.tr())` ولا `Text(label)` ولا `Text('a' + b)`، ولا النصوص اللي مفيهاش
ولا حرف (`'-'`، `'42 %'`، `'$count'`). الحروف العربي بتتحسب حروف عادي.

## 🧮 قواعد الـ ratchet بالتفصيل

| الحالة | النتيجة |
|---|---|
| العدد في فايل = الـ baseline | ✅ تمام |
| العدد زاد في فايل موجود في الـ baseline | ❌ error |
| فايل مش في الـ baseline وفيه مخالفات | ❌ error لكل مخالفة (إلا لو «نقل»، تحت) |
| العدد نزل | ❌ error «stale»: شغّل `update-baseline` وثبّت التحسين |
| **نقل (move)**: مخالفات في فايل جديد، ومجموع القاعدة ما زادش | ℹ️ مسموح (split أو rename مش دين جديد) |
| نقل لفايل كان موجود في الـ merge-base | ❌ ده مقايضة: صلّحت هنا وزوّدت هناك |
| `--base`: entry أعلى من الـ merge-base | ❌ error، أو ⚠️ warning لو معاه `reason` |
| `--base`: entry جديد ومجموع القاعدة زاد | ❌ error (أو ⚠️ مع `reason`) |

ليه الـ stale بيفشل؟ عشان لو ما ثبّتّش التحسين، أول PR بعدك يقدر يرجّع نفس العدد من غير ما حد يحس.

## 🤖 GitHub Action

</div>

```yaml
# .github/workflows/quality.yml
name: quality
on:
  pull_request:

jobs:
  ratchet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # الـ raise guard محتاج الـ merge-base
      - uses: youssef336/flutter_quality_ratchet@v1
        # with:
        #   working-directory: app          # لو المشروع في فولدر جوه الـ repo
        #   base-ref: origin/main           # الافتراضي: origin/${{ github.base_ref }}
        #   version: v0.1.0                 # الافتراضي: نفس نسخة الـ action
```

<div dir="rtl">

الـ action بيسطّب Dart، وبيفعّل الأداة من نفس الـ ref بتاع الـ action، وبيشغّل
`check --format github --base <base-ref>`. المخالفات بتظهر annotations على سطور الـ PR،
وجدول الـ rules بيظهر في الـ job summary. في الـ push (من غير base) بيشتغل من غير `--base`.

## ❓ أسئلة

<details>
<summary><b>لازم أعمل استثناء مستعجل (hotfix) ومش وقت تنضيف. أعمل إيه؟</b></summary>

علّي الـ entry بإيدك في نفس الـ PR، واكتب السبب:

</div>

```json
"no_print": {
  "lib/features/payment/checkout.dart": {"count": 3, "reason": "hotfix #214, cleanup in #215"}
}
```

<div dir="rtl">

الـ check هيعدّي، بس الـ raise guard هيطلّع **warning** فيه السبب على الـ PR، فالـ reviewer
شايفه وبيوافق عليه عن قصد. من غير `reason` الرفع ده error. وأول ما العدد ينزل تاني،
`update-baseline` بيشيل الـ reason لوحده.

</details>

<details>
<summary><b>قسمت فايل كبير لتلات فايلات، والـ check بيقول new path؟</b></summary>

لو مجموع القاعدة ما زادش والفايلات جديدة، ده «نقل» ومسموح (notice). شغّل
`update-baseline` عشان يسجّل المسارات الجديدة ويشيل القديم.

</details>

<details>
<summary><b>ضفت قاعدة جديدة للإعدادات، والـ check بيطلع exit 2؟</b></summary>

عادي: القاعدة ملهاش section في الـ baseline. شغّل `quality_ratchet seed-rule <id>` مرة واحدة،
وده بيجمّد الدين الحالي للقاعدة دي بس. ولو شلت قاعدة، `update-baseline` بيشيل الـ section بتاعتها.

</details>

<details>
<summary><b>ممكن أشغّلها من غير --base؟</b></summary>

أيوه، كل حاجة شغالة. اللي بيقف: الـ raise guard، وتحذير الفايلات الجديدة، والتأكد إن «النقل»
لفايل جديد فعلًا. في الـ CI استخدم `--base` دايمًا.

</details>

<details>
<summary><b>monorepo؟</b></summary>

حط `quality_ratchet.yaml` في فولدر المشروع، وشغّل `quality_ratchet -C app check` أو
`working-directory: app` في الـ action. الـ git commands بتشتغل نسبةً للفولدر ده.

</details>

## ⚖️ الحدود

- مش parser كامل لـ Dart: lexer صغير بيفرّق الكود عن التعليقات والـ strings. ده كفاية
  للقواعد دي، بس `max_function_lines` heuristic: مش بيقيس الـ closures ولا `=>`،
  ومش بيقيس constructor عنده initializer list قبل الـ `{`.
- `hardcoded_strings` بيمسك الـ literal المتباصي مباشرة بس، مش اللي في متغير الأول.
- الـ regex في `forbidden_patterns` بيشوف الكود بس؛ مينفعش تدوّر بيه جوه نص string.
- الـ raise guard بيحرس الـ baseline، مش ملف الإعدادات: لو حد خفّف `fail_above` أو شال قاعدة،
  ده بيبان في الـ diff بتاع `quality_ratchet.yaml` في الـ review.

</div>

## 🛠 Tech stack

- Dart 3.9+, no Flutter dependency (it reads source files, so it works on any Dart or Flutter repo).
- `package:args` for the CLI, `package:yaml` for the config. Everything else (lexer, globs,
  import resolution, the ratchet) is plain Dart with unit tests.
- `git` (only with `--base`): `merge-base`, `show` and `ls-tree`.

## 🏗 Project structure

| File | Role |
|---|---|
| `bin/quality_ratchet.dart` | thin entry point (also `bin/flutter_quality_ratchet.dart` for `dart run`) |
| `lib/src/cli/cli.dart` | argument parsing, file and git IO, writing the baseline |
| `lib/src/cli/project.dart` | file collection, pubspec reading, git wrapper |
| `lib/src/cli/init_template.dart` | the commented sample config |
| `lib/src/config.dart` | `quality_ratchet.yaml` parsing and validation |
| `lib/src/engine.dart` | the whole run as a pure function (`runRatchet`) |
| `lib/src/source/dart_scanner.dart` | comment/string stripping, literal spans, line counting |
| `lib/src/glob.dart` | glob matching |
| `lib/src/rules/*.dart` | one file per rule type |
| `lib/src/ratchet/baseline.dart` | baseline model, parsing, stable encoding |
| `lib/src/ratchet/ratchet.dart` | compare, shrink-only update, move rule, raise guard |
| `lib/src/report/reporters.dart` | text, GitHub annotations, JSON, job summary |
| `action.yml` | composite GitHub Action |

## 🧪 Development

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

## 📄 License

MIT, see [LICENSE](LICENSE).
