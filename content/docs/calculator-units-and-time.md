---
title: Calculator, units and time
description: Offline math and conversions, plus reminders and calendar events written as sentences.
weight: 40
---

All of these run locally. Nothing is sent anywhere until you activate a result that opens your browser.

## Calculator

Type an expression and the result appears as you type. `Enter` copies it.

```text
12*7+3
20% of 250
sqrt(2) * pi
2^10
```

Supported constants are `pi`, `tau` and `e`. Supported functions:

| Group | Functions |
| --- | --- |
| Roots and rounding | `sqrt`, `cbrt`, `abs`, `round`, `floor`, `ceil`, `sign` |
| Trigonometry | `sin`, `cos`, `tan`, `asin`, `acos`, `atan` |
| Logarithms | `ln`, `log`, `log2`, `exp` |
| Comparison | `min`, `max`, `pow`, `hypot` |

Percentages understand `x% of y`. Very large and very small results switch to a compact notation.

## Unit conversion

Write an amount, a unit, a connecting word and a target unit:

```text
10 km to miles
72 f in c
500 GB as GiB
3 hours to minutes
```

`to`, `in`, `as`, `->` and `=` all work as the connector. Conversions cover these families:

| Family | Examples |
| --- | --- |
| Length | `m`, `km`, `cm`, `mm`, `mi`, `yd`, `ft`, `in`, `nmi`, `ly`, `au` |
| Mass | `kg`, `g`, `mg`, `t`, `lb`, `oz`, `st` |
| Data | `B`, `KB`, `MB`, `GB`, `TB`, `KiB`, `MiB`, `GiB`, `TiB` |
| Duration | `ms`, `s`, `min`, `h`, `d`, `week` |
| Speed | `m/s`, `km/h`, `mph`, `kn` |
| Volume | `l`, `ml`, `gal`, `qt`, `pt`, `cup`, `floz` |
| Area | `m2`, `km2`, `ha`, `acre`, `ft2` |
| Temperature | `c`, `f`, `k` |

Both families must match and the units must belong to the same family. Spelled-out names like `meters`, `pounds` or `hours` work too.

## Reminders

Spotlight turns a sentence into an `omarchy reminder`:

```text
remind me in 20m to check the oven
remind me tomorrow at 9 to call the bank
remind me friday at noon to submit the report
```

Relative offsets such as `in 20m`, `in 2h` or `in 3 days` are counted from now. Absolute times understand `today`, `tonight`, `tomorrow`, weekdays, `next friday`, `at noon`, `at midnight`, `at 15:30` and `at 3pm`. A bare hour that has already passed rolls forward to the next sensible occurrence.

Type `reminders` to show or clear pending reminders.

## Calendar events

Describe the meeting and Spotlight builds an event:

```text
meeting with sarah tomorrow at 14:00 for 90min
dentist next tuesday at 8:30
```

`Enter` opens the event in Google Calendar in your browser. `Shift+Enter` writes an `.ics` file instead, which any calendar application can import. Durations accept `for 90min`, `for 2h` or `for 1.5 hours`; without one the event is an hour long.
