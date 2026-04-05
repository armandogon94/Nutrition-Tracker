'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { loginUser } from '@/lib/api';
import { setToken, setUser } from '@/lib/auth';

const TEST_ACCOUNTS = [
  { email: 'test1@fittracker.dev', password: 'test1234', label: 'Test 1' },
  { email: 'test2@fittracker.dev', password: 'test1234', label: 'Test 2' },
  { email: 'test3@fittracker.dev', password: 'test1234', label: 'Test 3' },
];

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (loginEmail: string, loginPassword: string) => {
    setError('');
    setLoading(true);
    try {
      const res = await loginUser(loginEmail, loginPassword);
      setToken(res.access_token);
      setUser(res.user);
      window.location.href = '/dashboard';
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Login failed';
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    handleLogin(email, password);
  };

  return (
    <div className="min-h-screen bg-gray-900 flex items-center justify-center px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-white">FitTracker</h1>
          <p className="text-gray-400 text-sm mt-1">Sign in to your account</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm text-gray-300 mb-1">Email</label>
            <input
              id="email"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-3 py-2 bg-gray-800 border border-gray-700 rounded text-white placeholder-gray-500 focus:outline-none focus:border-cyan-400"
              placeholder="you@example.com"
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm text-gray-300 mb-1">Password</label>
            <input
              id="password"
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 bg-gray-800 border border-gray-700 rounded text-white placeholder-gray-500 focus:outline-none focus:border-cyan-400"
              placeholder="Enter your password"
            />
          </div>

          {error && (
            <p className="text-red-400 text-sm text-center">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 bg-cyan-600 text-white rounded font-medium hover:bg-cyan-700 disabled:opacity-50 transition-colors"
          >
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <div className="text-center">
          <Link href="/register" className="text-cyan-400 text-sm hover:underline">
            Create Account
          </Link>
        </div>

        {process.env.NODE_ENV !== 'production' && (
        <div className="border-t border-gray-800 pt-4">
          <p className="text-xs text-gray-500 text-center mb-3">Quick login (test accounts)</p>
          <div className="flex gap-2">
            {TEST_ACCOUNTS.map((acct) => (
              <button
                key={acct.email}
                onClick={() => handleLogin(acct.email, acct.password)}
                disabled={loading}
                className="flex-1 py-2 bg-gray-800 text-gray-300 rounded text-xs hover:bg-gray-700 disabled:opacity-50 transition-colors"
              >
                {acct.label}
              </button>
            ))}
          </div>
        </div>
        )}
      </div>
    </div>
  );
}
