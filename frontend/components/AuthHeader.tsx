'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getUser, clearToken } from '@/lib/auth';

export default function AuthHeader() {
  const router = useRouter();
  const [displayName, setDisplayName] = useState<string | null>(null);

  useEffect(() => {
    const user = getUser();
    setDisplayName(user?.display_name ?? null);
  }, []);

  if (!displayName) return null;

  const handleLogout = () => {
    clearToken();
    router.push('/login');
  };

  return (
    <header className="fixed top-0 inset-x-0 z-50 bg-[#111827] border-b border-gray-800">
      <div className="max-w-2xl mx-auto flex items-center justify-between px-4 py-2">
        <span className="text-sm text-gray-300 truncate">{displayName}</span>
        <button
          onClick={handleLogout}
          className="text-xs text-gray-400 hover:text-red-400 transition-colors px-2 py-1"
        >
          Logout
        </button>
      </div>
    </header>
  );
}
