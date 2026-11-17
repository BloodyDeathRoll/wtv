/**
 * English and Hebrew display names for provider categories (P1-6).
 *
 * The provider writes most names as "English - עברית"; those are split. The
 * rest are Hebrew only, and translated from the table below. A Hebrew-only
 * name not in the table has no English name, and the app shows the Hebrew.
 */

/** Hebrew-only provider names, as the provider writes them. */
const ENGLISH: Record<string, string> = {
  'רדיו': 'Radio',
  '2024-2026 סרטים': 'Movies 2024–2026',
  'סרטים': 'Movies',
  'סרטים ב-4K': '4K Movies',
  'סרטים ישראליים': 'Israeli Movies',
  'סרטים הודיים': 'Indian Movies',
  'סרטי ילדים': 'Kids’ Movies',
  'עולם הפסטיגל': 'Festigal',
  'סטנד אפ': 'Stand-up',
  'סרטים - טבע, תיעודי, דוקו': 'Nature & Documentaries',
  'הופעות': 'Concerts',
  'אימה': 'Horror',
  'דרמה': 'Drama',
  'אקשן': 'Action',
  'אנימציה': 'Animation',
  'פשע': 'Crime',
  'קומדיה': 'Comedy',
  'רומנטי': 'Romance',
  'מדע בדיוני': 'Sci-Fi',
  'הרפתקאות ומשפחה': 'Adventure & Family',
  'מותחן - מסתורין': 'Thriller & Mystery',
  'מערבון - מלחמה': 'Western & War',
  'סדרות ישראליות': 'Israeli Series',
  'סדרות מהעולם': 'International Series',
  'סדרות טורקיות': 'Turkish Series',
  'סדרות ספרדיות': 'Spanish Series',
  'סדרות קוריאניות': 'Korean Series',
  'סדרות ודרמות הודיות': 'Indian Series & Dramas',
  'סדרות ילדים ואנימציה': 'Kids & Animation',
  'אנימה': 'Anime',
}

const hasHebrew = (s: string) => /[֐-׿]/.test(s)
const hasLatin = (s: string) => /[A-Za-z]/.test(s)
const tidy = (s: string) => s.replace(/\s+/g, ' ').trim()
/** "israel" → "Israel"; other casing is kept ("HBO Max", "Apple TV+"). */
const capitalise = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

export function categoryNames(raw: string): { en: string | null; he: string } {
  const name = tidy(raw)
  // The table comes first: some Hebrew-only names contain " - " too
  // ("מותחן - מסתורין"), and the split below would misread them.
  // Own keys only: "constructor" must not find Object.prototype's.
  if (Object.hasOwn(ENGLISH, name)) return { en: ENGLISH[name]!, he: name }

  // "English - עברית": Latin on the left, Hebrew on the right.
  const split = name.split(' - ')
  if (split.length === 2) {
    const [left, right] = split.map(tidy) as [string, string]
    if (hasLatin(left) && !hasHebrew(left) && hasHebrew(right)) return { en: capitalise(left), he: right }
  }

  if (!hasHebrew(name)) return { en: capitalise(name), he: name }
  return { en: null, he: name }
}
