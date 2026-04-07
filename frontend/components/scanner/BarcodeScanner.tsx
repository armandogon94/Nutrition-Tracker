"use client";

import { useEffect, useRef, useState, useCallback } from "react";

interface BarcodeScannerProps {
  onScan: (barcode: string) => void;
  onError?: (error: string) => void;
}

function safeStopScanner(scanner: any) {
  if (!scanner) return;
  try {
    const state = scanner.getState?.();
    // Only stop if actually scanning (state 2 = SCANNING, state 3 = PAUSED)
    if (state !== undefined && state !== 2 && state !== 3) return;
    const result = scanner.stop();
    if (result && typeof result.catch === "function") {
      result.catch(() => {});
    }
  } catch {
    // Scanner may throw synchronously if not running — ignore
  }
}

export default function BarcodeScanner({ onScan, onError }: BarcodeScannerProps) {
  const [isScanning, setIsScanning] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const scannerRef = useRef<any>(null);
  const onScanRef = useRef(onScan);
  const onErrorRef = useRef(onError);

  onScanRef.current = onScan;
  onErrorRef.current = onError;

  const startScanner = useCallback(async (mounted: { current: boolean }) => {
    try {
      const { Html5Qrcode } = await import("html5-qrcode");

      if (!mounted.current) return;

      const el = document.getElementById("barcode-reader");
      if (!el) return;

      const scanner = new Html5Qrcode("barcode-reader");
      scannerRef.current = scanner;

      await scanner.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 250, height: 150 } },
        (decodedText) => {
          safeStopScanner(scanner);
          setIsScanning(false);
          onScanRef.current(decodedText);
        },
        () => {}
      );

      if (mounted.current) setIsScanning(true);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Camera access denied";
      if (mounted.current) {
        setCameraError(message);
        onErrorRef.current?.(message);
      }
    }
  }, []);

  useEffect(() => {
    const mounted = { current: true };
    startScanner(mounted);

    return () => {
      mounted.current = false;
      safeStopScanner(scannerRef.current);
      scannerRef.current = null;
    };
  }, [startScanner]);

  if (cameraError) {
    return (
      <div className="text-center p-6 bg-red-900/30 border border-red-700 rounded-xl">
        <p className="text-red-300 mb-2">Camera unavailable</p>
        <p className="text-sm text-gray-400">{cameraError}</p>
        <p className="text-sm text-gray-400 mt-2">
          Use manual barcode entry below
        </p>
      </div>
    );
  }

  return (
    <div className="relative">
      <div
        id="barcode-reader"
        className="w-full max-w-md mx-auto rounded-xl overflow-hidden border-2 border-cyan-500/50"
      />
      {isScanning && (
        <p className="text-center text-sm text-gray-400 mt-3">
          Point camera at a barcode
        </p>
      )}
    </div>
  );
}
