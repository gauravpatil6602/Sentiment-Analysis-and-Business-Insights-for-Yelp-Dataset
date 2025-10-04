CREATE OR REPLACE FUNCTION analyze_sentiment(review STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('vaderSentiment','emoji')
HANDLER = 'sentiment_analyzer'
AS $$
import re
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
import emoji

# Create analyzer once (efficient when Snowflake re-uses the worker)
_analyzer = SentimentIntensityAnalyzer()

# Minimal contraction map to improve handling of negation
_CONTRACTIONS = {
    "can't": "can not", "won't": "will not", "n't": " not", "'re": " are",
    "'m": " am", "'ll": " will", "'ve": " have", "'s": " is"
}

# Common intensifier words
_INTENSIFIERS = {"very","extremely","absolutely","incredibly","so","totally","completely","really","super","too"}

def _preprocess(text: str) -> str:
    """Simple preprocessing: handle emojis, contractions, repeated characters, spacing."""
    if text is None:
        return ""
    try:
        text = emoji.demojize(text)
    except Exception:
        pass
    text = text.replace(":", " ").replace("_", " ")
    txt = text
    for k, v in _CONTRACTIONS.items():
        txt = re.sub(re.escape(k), v, txt, flags=re.IGNORECASE)
    txt = re.sub(r'(.)\1{2,}', r'\1\1', txt)
    txt = re.sub(r'\s+', ' ', txt).strip()
    return txt

def _compute_bonus_flags(text: str):
    """Compute small heuristic bonuses based on punctuation, ALL CAPS and intensifiers."""
    exclaim_count = text.count('!')
    exclaim_bonus = min(0.08 * exclaim_count, 0.20)
    words = re.findall(r"\w+", text)
    allcaps = sum(1 for w in words if len(w) > 1 and w.isupper())
    allcaps_ratio = (allcaps / len(words)) if words else 0.0
    caps_bonus = 0.07 if allcaps_ratio > 0.30 else 0.0
    intens_count = sum(1 for w in (w.lower() for w in words) if w in _INTENSIFIERS)
    intens_bonus = min(0.05 * intens_count, 0.15)
    return exclaim_bonus, caps_bonus, intens_bonus

def sentiment_analyzer(review):
    """Return only the sentiment label: Positive / Neutral / Negative"""
    text = _preprocess(review or "")
    if not text:
        return "Neutral"

    scores = _analyzer.polarity_scores(text)
    vader_compound = float(scores.get("compound", 0.0))

    exclaim_bonus, caps_bonus, intens_bonus = _compute_bonus_flags(text)

    final = vader_compound
    if final > 0:
        final = min(1.0, final + exclaim_bonus + caps_bonus + intens_bonus)
    elif final < 0:
        final = max(-1.0, final - exclaim_bonus - caps_bonus - intens_bonus)

    if final >= 0.30:
        return "Positive"
    elif final <= -0.30:
        return "Negative"
    else:
        return "Neutral"
$$;


select * from tbl_yelp_reviews limit 100;

select * from tbl_yelp_businesses limit 100;

