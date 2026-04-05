export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem('fittracker_token');
}

export function setToken(token: string): void {
  localStorage.setItem('fittracker_token', token);
}

export function clearToken(): void {
  localStorage.removeItem('fittracker_token');
  localStorage.removeItem('fittracker_user');
}

export function getUser(): { id: string; email: string; display_name: string } | null {
  if (typeof window === 'undefined') return null;
  const u = localStorage.getItem('fittracker_user');
  if (!u) return null;
  try {
    return JSON.parse(u);
  } catch {
    return null;
  }
}

export function setUser(user: { id: string; email: string; display_name: string }): void {
  localStorage.setItem('fittracker_user', JSON.stringify(user));
}

export function isTokenExpired(): boolean {
  const token = getToken();
  if (!token) return true;
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.exp * 1000 < Date.now();
  } catch {
    return true;
  }
}

export function isLoggedIn(): boolean {
  return !!getToken() && !isTokenExpired();
}
