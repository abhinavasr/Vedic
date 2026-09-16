# Astronomical reference data

Ground truth for the panchang maths, fetched from **NASA/JPL Horizons** — US Government work,
public domain, no licensing entanglement with a closed-source app. The two shell scripts here
are the exact queries that produced the CSVs; re-run them to regenerate.

Astronomical code cannot be reviewed by reading it. It looks correct and is silently ten
minutes out. These files exist so the tests can say *how wrong* the implementation is, in
arcseconds, against a source nobody disputes.

## `sun_moon.csv` — 1827 instants, 1900 → 2100

Apparent geocentric ecliptic longitude of date, in degrees, for the Sun and the Moon, plus the
Moon's ecliptic latitude.

Sampled every **40 days**, deliberately: the synodic month is 29.53 days, so a 30-day step would
land on nearly the same lunar phase every time and a phase-dependent error would never show up.
40 days walks through every phase and every season across two centuries.

These two longitudes are the whole of the panchang's astronomy:

| Anga | Definition |
|---|---|
| Tithi | ⌈(Moon − Sun) / 12°⌉ — 30 per lunation |
| Nakṣatra | Moon's **sidereal** longitude / 13°20′ — 27 divisions |
| Yoga | (Moon + Sun) sidereal / 13°20′ — 27 divisions |
| Karaṇa | half a tithi — 6° of elongation |

Horizons returns **tropical** (of-date) longitudes. Nakṣatra and yoga are sidereal, so an
ayanāṃśa is subtracted — which is a convention, not an observation, and does not belong in a
fixture file. The tests check the tropical longitudes against these numbers and check the
ayanāṃśa separately.

## `rise_set.csv` — 410 events, six cities

Rise, transit and set of the Sun and the Moon, in UTC, for Delhi, Bengaluru, Kolkata, London,
Sydney and Tromsø, over four three-day windows at the equinoxes and solstices of 2026.

**Site elevation is deliberately 0.** Horizons subtracts horizon dip for a site above sea level
— at Delhi's 216 m that is 26 arcminutes, about two minutes of time — but Indian panchang
convention computes sunrise for the sea-level horizon. The fixtures match the convention the app
implements rather than the geography of the city.

The cities are chosen for what they break, not for where users are:

- **Bengaluru** (12.97°N) — near-equatorial, rise and set barely move across the year.
- **Delhi, Kolkata** — the ordinary case, and two longitudes inside one time zone, which is
  where "sunrise in India" stops being one number.
- **London** (51.5°N) — long summer days, and a time zone that changes twice a year.
- **Sydney** (33.9°S) — southern hemisphere: the seasons invert and so does the Moon's path.
- **Tromsø** (69.6°N) — **above the Arctic circle**. In the 21 June window the Sun neither rises
  nor sets: the file contains transits and no rise or set events at all. A panchang that assumes
  every day has a sunrise divides by zero, or hangs, or silently reports nonsense. Anyone in the
  diaspora north of 66° hits this every year, and it is in the fixtures from the first day
  rather than being found in the wild.
