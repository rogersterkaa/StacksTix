"use client";

import { useState, useEffect } from "react";

export default function Home() {
  const [address, setAddress] = useState<string>("");

  const connectWallet = async () => {
    try {
      // @ts-ignore - Leather wallet injects this
      if (window.LeatherProvider) {
        // @ts-ignore
        const provider = window.LeatherProvider;
        const response = await provider.request('getAddresses');
        if (response.result && response.result.addresses) {
          const testnetAddress = response.result.addresses.find(
            (addr: any) => addr.type === 'stacks' && addr.symbol === 'STX'
          );
          if (testnetAddress) {
            setAddress(testnetAddress.address);
          }
        }
      } else {
        alert("Please install Leather Wallet extension");
      }
    } catch (error) {
      console.error("Connection failed:", error);
      alert("Failed to connect wallet");
    }
  };

  const disconnectWallet = () => {
    setAddress("");
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-black">
      <nav className="bg-black/30 backdrop-blur-md border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex justify-between items-center">
            <h1 className="text-3xl font-bold text-white">🎟️ StacksTix</h1>
            {address ? (
              <div className="flex items-center gap-4">
                <span className="text-white/80">
                  {address.slice(0, 8)}...{address.slice(-6)}
                </span>
                <button
                  onClick={disconnectWallet}
                  className="bg-red-600 hover:bg-red-700 text-white px-6 py-2 rounded-lg"
                >
                  Disconnect
                </button>
              </div>
            ) : (
              <button
                onClick={connectWallet}
                className="bg-purple-600 hover:bg-purple-700 text-white px-8 py-3 rounded-lg"
              >
                Connect Wallet
              </button>
            )}
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto px-4 py-12">
        <div className="text-center mb-12">
          <h2 className="text-5xl font-bold text-white mb-4">
            Bitcoin-Secured NFT Ticketing
          </h2>
          <p className="text-xl text-white/70 mb-8">
            Live on Stacks Testnet
          </p>
          
          {!address && (
            <div className="bg-yellow-500/20 border border-yellow-500/50 rounded-lg p-6 max-w-2xl mx-auto">
              <p className="text-yellow-200">
                👆 Connect your Leather Wallet to continue
              </p>
            </div>
          )}

          {address && (
            <div className="bg-green-500/20 border border-green-500/50 rounded-lg p-6 max-w-2xl mx-auto">
              <p className="text-green-200 text-xl mb-2">
                ✅ Wallet Connected!
              </p>
              <p className="text-green-100 text-sm font-mono">
                {address}
              </p>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}