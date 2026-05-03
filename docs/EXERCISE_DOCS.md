# Exercise Documentation Reference

IronLog keeps exercise execution guidance in a separate Mongo collection,
`exercise_docs`, keyed by `exercise_slug + locale`. The exercise catalog remains
the identity layer; exercise docs are the education/content layer.

## API

Public reads:

```text
GET /exercise-docs?locale=ru
GET /exercise-docs?locale=ru&status=reviewed
GET /exercise-docs/missing?locale=ru&status=reviewed
GET /exercises/{slug}/docs?locale=ru
```

JWT writes:

```text
PUT /exercises/{slug}/docs?locale=ru
```

The server owns `content_version`. Every successful PUT increments it by one.
Authors must not manually pick a version number.

## Document Shape

```json
{
  "title": "Жим ногами",
  "summary": "Короткое описание назначения упражнения.",
  "setup": ["Как настроить тренажер и стартовую позицию."],
  "execution": ["Как выполнить повторение."],
  "breathing": "Как дышать.",
  "cues": ["Короткие подсказки во время подхода."],
  "common_mistakes": ["Типичные ошибки."],
  "safety_notes": ["Ограничения и стоп-сигналы."],
  "alternative_slugs": ["leg_extension_machine"],
  "media": [{
    "kind": "image",
    "url": "https://example.com/owned-image.png",
    "alt": "Описание изображения",
    "source": "IronLog",
    "license": "owned",
    "attribution": ""
  }],
  "sources": [{
    "title": "Exercise Library",
    "publisher": "ACE",
    "url": "https://www.acefitness.org/resources/everyone/exercise-library/",
    "type": "exercise_library",
    "notes": "Used for movement-specific technique review."
  }],
  "status": "draft"
}
```

`sources` is required. `media` stores metadata and URLs only; do not store image
binaries in Mongo. Use owned, generated, licensed, or explicitly reusable media.
Do not scrape copyrighted exercise photos into the product.

## Status Rules

- `draft`: authored but not reviewed; safe for internal AI/authoring workflows.
- `reviewed`: app-ready. Mark only after source review and human sanity check.
- `deprecated`: preserved for history, hidden from product surfaces by default.

## Source Priority

Use a source stack instead of a single source:

1. Government/health authority guidance for general safety and dose:
   - HHS/ODPHP Physical Activity Guidelines:
     https://odphp.health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines/about-physical-activity-guidelines
   - NHS strength guidance:
     https://www.nhs.uk/live-well/exercise/how-to-improve-strength-flexibility/
2. Professional exercise science guidance:
   - ACSM progression models:
     https://www.acsm.org/wp-content/uploads/2025/01/Progression-Models-in-Resistance-Training-for-Healthy-Adults.pdf
   - ACSM resistance training injury prevention:
     https://www.acsm.org/docs/default-source/files-for-resource-library/smb-resistance-training-and-injury-prevention.pdf
3. Exercise-specific technique libraries:
   - ACE Exercise Library:
     https://www.acefitness.org/resources/everyone/exercise-library/
   - NASM Exercise Library:
     https://www.nasm.org/resource-center/exercise-library
4. Research papers for specific disputed claims, when useful.

IFBB/Mr. Olympia materials are not a primary source for exercise safety or
rehabilitation guidance. They can be useful for bodybuilding context, but public
official material is mostly competition/media content rather than evidence-based
exercise instruction.

## Authoring Rules

- Write original text. Paraphrase; do not copy full exercise instructions from
  third-party sources.
- Keep claims practical and conservative: setup, movement path, controlled
  tempo, range of motion, common mistakes, and stop conditions.
- For users with spine restrictions, prefer supported/machine variants where
  equivalent and explicitly warn on axial-loading movements.
- If an instruction depends on a specific machine, say so and keep it general.
- If sources disagree, choose the safer, more conservative instruction and add a
  source note.
