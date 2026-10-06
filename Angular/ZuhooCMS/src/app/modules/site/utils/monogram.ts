/** The company's initials, used wherever a logo is expected but none has been uploaded, instead of a generic stock icon. */
export function monogramOf(companyName?: string | null): string {
  const name = companyName?.trim();
  if (!name) return '—';
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w.charAt(0).toUpperCase())
    .join('');
}
