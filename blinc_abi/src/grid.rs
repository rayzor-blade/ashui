//! CSS grid values, from the text CSS writes them in to taffy's types.
//!
//! Lengths are in px; ashui's CSS resolves em, rem and viewport units before
//! they reach here. A value that does not parse is `None`, and the property
//! keeps its default.

use taffy::prelude::*;
use taffy::{CheapCloneStr, GridTemplateComponent, MaxTrackSizingFunction, MinTrackSizingFunction, RepetitionCount};

/// Splits `s` at top-level occurrences of `sep`, leaving parentheses whole.
fn split_top(s: &str, sep: char) -> Vec<&str> {
    let mut out = Vec::new();
    let (mut depth, mut start) = (0i32, 0usize);
    for (i, c) in s.char_indices() {
        match c {
            '(' => depth += 1,
            ')' => depth -= 1,
            c if depth == 0 && (c == sep || (sep == ' ' && c.is_whitespace())) => {
                if i > start {
                    out.push(&s[start..i]);
                }
                start = i + c.len_utf8();
            }
            _ => {}
        }
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out.into_iter().map(str::trim).filter(|t| !t.is_empty()).collect()
}

/// The inside of `name(...)`, if `s` is that call.
fn call<'a>(s: &'a str, name: &str) -> Option<&'a str> {
    s.strip_prefix(name)?.trim_start().strip_prefix('(')?.strip_suffix(')')
}

fn number(s: &str, unit: &str) -> Option<f32> {
    s.strip_suffix(unit)?.trim().parse().ok()
}

/// A length or percentage as `px` and `percent` make it: percentages are fractions.
fn fixed<T>(s: &str, px: fn(f32) -> T, percent: fn(f32) -> T) -> Option<T> {
    if let Some(p) = number(s, "%") {
        return Some(percent(p / 100.0));
    }
    number(s, "px").or_else(|| s.parse().ok()).map(px)
}

fn min_track(s: &str) -> Option<MinTrackSizingFunction> {
    Some(match s {
        "auto" => MinTrackSizingFunction::auto(),
        "min-content" => MinTrackSizingFunction::min_content(),
        "max-content" => MinTrackSizingFunction::max_content(),
        _ => fixed(s, MinTrackSizingFunction::length, MinTrackSizingFunction::percent)?,
    })
}

/// A track's maximum, and whether the track is flexible (`fr` or `fit-content`).
fn max_track(s: &str) -> Option<(MaxTrackSizingFunction, bool)> {
    Some(match s {
        "auto" => (MaxTrackSizingFunction::auto(), false),
        "min-content" => (MaxTrackSizingFunction::min_content(), false),
        "max-content" => (MaxTrackSizingFunction::max_content(), false),
        _ => {
            if let Some(f) = number(s, "fr") {
                (MaxTrackSizingFunction::fr(f), true)
            } else if let Some(arg) = call(s, "fit-content") {
                let limit = fixed(arg.trim(), LengthPercentage::length, LengthPercentage::percent)?;
                (MaxTrackSizingFunction::fit_content(limit), true)
            } else {
                (fixed(s, MaxTrackSizingFunction::length, MaxTrackSizingFunction::percent)?, false)
            }
        }
    })
}

/// One track: a size, `minmax(min, max)` or `fit-content(length)`.
fn track(s: &str) -> Option<TrackSizingFunction> {
    if let Some(args) = call(s, "minmax") {
        let parts = split_top(args, ',');
        let [min, max] = parts.as_slice() else { return None };
        return Some(minmax(min_track(min)?, max_track(max)?.0));
    }
    let (max, flexible) = max_track(s)?;
    // A flexible track's minimum is auto, as CSS has it.
    let min = if flexible { MinTrackSizingFunction::auto() } else { min_track(s)? };
    Some(minmax(min, max))
}

/// `grid-template-columns` or `-rows`: tracks and `repeat(count | auto-fill | auto-fit, tracks)`; `none` is no tracks.
pub fn template<S: CheapCloneStr>(s: &str) -> Option<Vec<GridTemplateComponent<S>>> {
    let s = s.trim();
    if s == "none" || s.is_empty() {
        return Some(Vec::new());
    }
    split_top(s, ' ')
        .into_iter()
        .map(|part| {
            if let Some(args) = call(part, "repeat") {
                let parts = split_top(args, ',');
                let (count, tracks) = parts.split_first()?;
                let kind = match *count {
                    "auto-fill" => RepetitionCount::AutoFill,
                    "auto-fit" => RepetitionCount::AutoFit,
                    n => RepetitionCount::Count(n.parse().ok().filter(|&n: &u16| n > 0)?),
                };
                let list = tracks
                    .iter()
                    .flat_map(|t| split_top(t, ' '))
                    .map(track)
                    .collect::<Option<Vec<_>>>()?;
                Some(repeat(kind, list))
            } else {
                track(part).map(GridTemplateComponent::Single)
            }
        })
        .collect()
}

fn placement(s: &str) -> Option<GridPlacement> {
    let words: Vec<&str> = s.split_whitespace().collect();
    match words.as_slice() {
        ["auto"] => Some(GridPlacement::Auto),
        ["span", n] => n.parse().ok().filter(|&n: &u16| n > 0).map(span),
        [n] => n.parse().ok().filter(|&n: &i16| n != 0).map(line),
        _ => None,
    }
}

/// `grid-column` or `grid-row`: `start`, or `start / end`, each a line, `span n` or `auto`.
pub fn line_pair(s: &str) -> Option<Line<GridPlacement>> {
    let parts: Vec<&str> = s.split('/').map(str::trim).collect();
    match parts.as_slice() {
        [start] => Some(Line { start: placement(start)?, end: GridPlacement::Auto }),
        [start, end] => Some(Line { start: placement(start)?, end: placement(end)? }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn templates() {
        assert_eq!(template("repeat(3, 1fr)").unwrap().len(), 1);
        assert_eq!(template("120px 1fr minmax(0, 2fr) auto 25%").unwrap().len(), 5);
        assert!(matches!(template("repeat(auto-fill, minmax(100px, 1fr))").unwrap()[0], TrackSizingFunction::Repeat(GridTrackRepetition::AutoFill, _)));
        assert!(template("1fr nonsense").is_none());
        assert!(template("repeat(0, 1fr)").is_none());
        assert_eq!(template("none").unwrap().len(), 0);
    }

    #[test]
    fn placements() {
        let l = line_pair("span 2").unwrap();
        assert_eq!(l.start, GridPlacement::Span(2));
        let l = line_pair("1 / -1").unwrap();
        assert_eq!(l.end, line(-1));
        assert!(line_pair("0").is_none());
        assert!(line_pair("1 / 2 / 3").is_none());
    }
}
