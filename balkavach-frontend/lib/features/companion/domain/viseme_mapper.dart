import 'viseme.dart';

/// Turns a spoken word into the mouth shapes it passes through.
///
/// This is an **approximation from spelling**, not phoneme recognition. The
/// platform text-to-speech only reports which word it is saying (no phonemes,
/// no audio), so the shapes are derived from the letters of that word. It
/// recognises English (Latin letters), Hindi (Devanagari) and Gujarati; Gujarati
/// shares Devanagari's layout, offset by 0x180.
///
/// The result never has two equal shapes in a row, is empty only for text with
/// no letters, and keeps lip closures (m, b, p), which are the most visible.
List<Viseme> visemesForWord(String word) {
  final raw = <Viseme>[];
  final runes = word.runes.toList();
  var latin = StringBuffer();

  void flushLatin() {
    if (latin.isEmpty) return;
    raw.addAll(_latinVisemes(latin.toString().toLowerCase()));
    latin = StringBuffer();
  }

  var i = 0;
  while (i < runes.length) {
    final rune = _toDevanagari(runes[i]);
    if (_isLatin(rune)) {
      latin.writeCharCode(rune);
      i++;
      continue;
    }
    flushLatin();
    if (rune >= 0x0900 && rune <= 0x097F) {
      i = _indic(runes, i, raw);
    } else {
      i++; // digits and punctuation make no shape of their own
    }
  }
  flushLatin();

  if (raw.isEmpty && _hasDigit(word)) raw.add(Viseme.ah);
  return _collapse(raw);
}

bool _hasDigit(String word) => word.runes.any((r) => r >= 0x30 && r <= 0x39);

bool _isLatin(int r) =>
    (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || r == 0x27;

/// Gujarati letters share Devanagari's order, 0x180 higher.
int _toDevanagari(int rune) =>
    rune >= 0x0A80 && rune <= 0x0AFF ? rune - 0x180 : rune;

List<Viseme> _collapse(List<Viseme> shapes) {
  final out = <Viseme>[];
  for (final shape in shapes) {
    if (out.isEmpty || out.last != shape) out.add(shape);
  }
  return out;
}

// ---- Latin ----------------------------------------------------------------

const _vowels = 'aeiouy';

List<Viseme> _latinVisemes(String w) {
  final out = <Viseme>[];
  var i = 0;
  // A silent final "e" after a consonant ("make", "joke") makes no shape.
  var end = w.length;
  if (end > 2 &&
      w.endsWith('e') &&
      !_vowels.contains(w[end - 2]) &&
      w.substring(0, end - 1).split('').any(_vowels.contains)) {
    end--;
  }
  bool at(String pair) => w.startsWith(pair, i) && i + pair.length <= end;

  while (i < end) {
    if (at('th')) {
      out.add(Viseme.tl);
      i += 2;
    } else if (at('ph')) {
      out.add(Viseme.fv);
      i += 2;
    } else if (at('oo') || at('ew') || at('ue')) {
      out.add(Viseme.oo);
      i += 2;
    } else if (at('ou') || at('ow') || at('oa') || at('au') || at('aw')) {
      out.add(Viseme.oh);
      i += 2;
    } else if (at('ee') || at('ea') || at('ie') || at('ei')) {
      out.add(Viseme.ee);
      i += 2;
    } else if (at('ai') || at('ay')) {
      out.add(Viseme.ah);
      out.add(Viseme.ee);
      i += 2;
    } else if (at('sh') || at('ch')) {
      out.add(Viseme.ee);
      i += 2;
    } else {
      out.add(_latinLetter(w, i, end));
      i++;
    }
  }
  return out;
}

Viseme _latinLetter(String w, int i, int end) {
  switch (w[i]) {
    case 'm' || 'b' || 'p':
      return Viseme.mbp;
    case 'f' || 'v':
      return Viseme.fv;
    case 'w' || 'q':
      return Viseme.oo;
    case 'o':
      return Viseme.oh;
    case 'a':
      return Viseme.ah;
    case 'e' || 'i' || 'y':
      return Viseme.ee;
    case 'u':
      // "cup" opens, "you" rounds: a vowel after it, or a leading u, rounds.
      final next = i + 1 < end ? w[i + 1] : '';
      return i == 0 || _vowels.contains(next) ? Viseme.oo : Viseme.ah;
    default:
      return Viseme.tl; // t d n l k g s z r h j x c ...
  }
}

// ---- Devanagari / Gujarati -------------------------------------------------

/// Consumes one consonant+matra (or a vowel) at [i]; returns the next index.
int _indic(List<int> r, int i, List<Viseme> out) {
  final c = _toDevanagari(r[i]);

  // Independent vowels.
  final independent = _independentVowel(c);
  if (independent != null) {
    out.add(independent);
    return i + 1;
  }

  // A consonant: its own shape, then its vowel sign, or the inherent "a".
  if (_isConsonant(c)) {
    out.add(_consonantShape(c));
    var j = i + 1;
    if (j < r.length && _toDevanagari(r[j]) == 0x093C) j++; // nukta
    if (j < r.length) {
      final next = _toDevanagari(r[j]);
      if (next == 0x094D) return j + 1; // virama: no vowel (conjunct)
      final sign = _vowelSign(next);
      if (sign != null) {
        out.add(sign);
        return j + 1;
      }
    }
    // Inherent short "a": spoken unless the consonant ends the word.
    final isLast = !r
        .skip(j)
        .any((x) => _isConsonant(_toDevanagari(x)) || _isVowelish(x));
    if (!isLast) out.add(Viseme.ah);
    return j;
  }
  return i + 1; // anusvara, visarga, digits, punctuation
}

bool _isVowelish(int rune) {
  final c = _toDevanagari(rune);
  return _independentVowel(c) != null;
}

bool _isConsonant(int c) =>
    c >= 0x0915 && c <= 0x0939 || c == 0x0958 || c == 0x0959;

Viseme _consonantShape(int c) => switch (c) {
  0x092A || 0x092B || 0x092C || 0x092D || 0x092E => Viseme.mbp, // प फ ब भ म
  0x0935 => Viseme.fv, // व
  0x0936 || 0x0937 || 0x091A || 0x091B || 0x091C || 0x091D => Viseme.ee,
  _ => Viseme.tl,
};

Viseme? _independentVowel(int c) => switch (c) {
  0x0905 || 0x0906 || 0x0972 => Viseme.ah, // अ आ
  0x0907 ||
  0x0908 ||
  0x090B ||
  0x090F ||
  0x0910 ||
  0x090D => Viseme.ee, // इ ई ऋ ए ऐ
  0x0909 || 0x090A => Viseme.oo, // उ ऊ
  0x0913 || 0x0914 || 0x0911 => Viseme.oh, // ओ औ
  _ => null,
};

Viseme? _vowelSign(int c) => switch (c) {
  0x093E => Viseme.ah, // ा
  0x093F || 0x0940 || 0x0943 || 0x0947 || 0x0948 || 0x0945 => Viseme.ee,
  0x0941 || 0x0942 => Viseme.oo,
  0x094B || 0x094C || 0x0949 => Viseme.oh,
  _ => null,
};
