export function nowTimestamp(): number {
  return Date.now();
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString();
}
