# Design notes

Why Zendish is built the way it is. For how to install and use it, see the [README](../README.md).

## Goals

- Free to build and run, with no paid services
- Runs entirely on an Apple Silicon Mac
- Every card can be checked against the image it came from
- Clean and minimal, with only the features it needs

## Key decisions

| Decision | Why |
|---|---|
| Native SwiftUI | Text recognition, HEIC images and PDF drawing come with macOS, which keeps the app small and leaves no helper program |
| macOS text recognition, then a text model | Recognition was accurate and fast on recipe screenshots, and a text model is smaller and easier to test than a vision model |
| `qwen3.5:9b` through Ollama | It was the most accurate model tested that runs on a 16 GB Mac, and it gave identical cards across repeat runs |
| Plain-code card checks after the model | Small models fill blanks and drop sections, and checks that use no AI behave the same way every time |
| Flags instead of silent fixes | A misread quantity is easy to miss, so a person always decides |
| Times and servings need a nearby label | This stops video timers, like counts and times from inside the method appearing on a card |
| Images with no ingredient lines skip the model | It's faster, and it avoids a case where a model repeated itself until it was stopped |
| A hard limit on the model's output | A stuck model can't hang a card forever |
| One card read at a time | The model uses most of the Mac's memory |
| Original images copied into app storage | Recipes keep working if the originals move |
| Cover photo chosen by hand | A drag is simple and always right, and there's no reliable way to find the food in every screenshot |
| SQLite full-text search | Dish and ingredient names work well with word search, so no embedding model is needed |
| Models and storage kept out of the UI | Almost everything can be tested without opening a window |

## What was left out

| Left out | Why |
|---|---|
| Accounts, syncing and public sharing | The app is local and personal |
| Shopping lists, meal plans and cooking timers | They aren't needed to turn a screenshot into a card |
| iPhone and Android versions | Phones that can run an accurate model are too limited, or can't be tested here |
| Apple's on-device model | It was four times faster with no download, but dropped a section and filled in wrong times |
| Highlighting flagged text in the image | Worth adding if finding the matching text proves slow |

## Lessons from testing

- **Text recognition has one repeated weakness.** It read `1 1/2` as `11/2` every time that format appeared, while `1 ½` was fine. Turning off language correction didn't help.
- **A better prompt isn't always better.** A more detailed prompt fixed dropped sections on `llama3.2`, but it also invented servings and failed on images with no recipe.
- **Check scores by hand.** Automatic scoring counted reference notes as quantities and headings as ingredients, which made real results look worse than they were.
- **Inspect the real window.** Rendering each screen found uneven card rows and bare numbers on cards that no unit test would catch.
