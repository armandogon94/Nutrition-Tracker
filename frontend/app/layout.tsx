import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Nutrition Tracker",
  description: "Track your nutrition with barcode scanning",
};

const navItems = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/scan", label: "Scan" },
  { href: "/meals", label: "Meals" },
  { href: "/goals", label: "Goals" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body className="min-h-screen flex flex-col">
        <main className="flex-1 max-w-2xl mx-auto w-full px-4 pb-24 pt-6">
          {children}
        </main>

        {/* Bottom navigation - mobile first */}
        <nav className="fixed bottom-0 inset-x-0 bg-[#111827] border-t border-gray-800">
          <div className="max-w-2xl mx-auto flex justify-around py-2">
            {navItems.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="flex flex-col items-center gap-1 px-3 py-1 text-xs text-gray-400 hover:text-cyan-400 transition-colors"
              >
                {item.label}
              </Link>
            ))}
          </div>
        </nav>
      </body>
    </html>
  );
}
