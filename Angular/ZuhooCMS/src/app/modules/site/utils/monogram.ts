/**
 * The company's initials, for use wherever a logo is expected but none has been
 * uploaded — the hero, the navbar brand, the footer brand. A generic stock icon
 * in that slot reads as filler on every tenant's site; the company's own letters
 * at least belong to this one.
 */
export function monogramOf(companyName?: string | null): string {
  const name = companyName?.trim();
  if (!name) return '—';
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w.charAt(0).toUpperCase())
    .join('');
}
