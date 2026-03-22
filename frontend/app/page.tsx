"use client";

import { useState } from "react";

export default function Home() {
  const [address, setAddress] = useState<string>("");
  const [events, setEvents] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  const contractAddress = "ST1B10ZBNJ3FP9K6BAFE1ZY46TYKYTHE66QS885YZ";

  const connectWallet = async () => {
    try {
      // @ts-ignore
      if (!window.LeatherProvider) {
        alert("Please install Leather Wallet extension");
        return;
      }

      // @ts-ignore
      const provider = window.LeatherProvider;
      const response = await provider.request('getAddresses');
      
      if (response?.result?.addresses) {
        // Find testnet STX address (starts with ST)
        const testnetAddr = response.result.addresses.find(
          (addr: any) => addr.symbol === 'STX' && addr.address.startsWith('ST')
        );
        
        if (testnetAddr) {
          setAddress(testnetAddr.address);
        } else {
          alert("No testnet address found. Make sure you're on Testnet4!");
        }
      }
    } catch (error) {
      console.error("Connection failed:", error);
      alert("Failed to connect. Make sure Leather Wallet is on Testnet4!");
    }
  };

  const disconnectWallet = () => {
    setAddress("");
    setEvents([]);
  };

  const loadEvents = () => {
    setLoading(true);
    
    const mockEvents = [
      {
        id: 1,
        name: { value: "Bitcoin Conference 2026" },
        location: { value: "Lagos Convention Center" },
        price: { value: "50000000" },
        "total-supply": { value: "100" },
        "tickets-sold": { value: "0" }
      },
      {
        id: 2,
        name: { value: "Stacks Developer Meetup" },
        location: { value: "Tech Hub Lagos" },
        price: { value: "25000000" },
        "total-supply": { value: "50" },
        "tickets-sold": { value: "0" }
      }
    ];
    
    setTimeout(() => {
      setEvents(mockEvents);
      setLoading(false);
    }, 1000);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-black">
      <nav className="bg-black/30 backdrop-blur-md border-b border-white/10">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex justify-between items-center">
            <h1 className="text-3xl font-bold text-white">🎟️ StacksTix</h1>
            {address ? (
              <div className="flex items-center gap-4">
                <span className="text-white/80 text-sm font-mono">
                  {address.slice(0, 8)}...{address.slice(-6)}
                </span>
                <button
                  onClick={disconnectWallet}
                  className="bg-red-600 hover:bg-red-700 text-white px-6 py-2 rounded-lg transition"
                >
                  Disconnect
                </button>
              </div>
            ) : (
              <button
                onClick={connectWallet}
                className="bg-purple-600 hover:bg-purple-700 text-white px-8 py-3 rounded-lg transition"
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
            <div className="bg-yellow-500/20 border border-yellow-500/50 rounded-lg p-6 max-w-2xl mx-auto mb-8">
              <p className="text-yellow-200">
                👆 Connect your Leather Wallet to browse events
              </p>
            </div>
          )}

          {address && (
            <div className="bg-green-500/20 border border-green-500/50 rounded-lg p-4 max-w-2xl mx-auto mb-8">
              <p className="text-green-200 text-lg">
                ✅ Wallet Connected!
              </p>
            </div>
          )}
        </div>

        {address && (
          <div className="mb-8 text-center">
            <button
              onClick={loadEvents}
              disabled={loading}
              className="bg-gradient-to-r from-green-600 to-teal-600 hover:from-green-700 hover:to-teal-700 text-white px-10 py-4 rounded-lg font-bold text-lg transition transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed shadow-lg"
            >
              {loading ? "🔍 Loading Events..." : "🎫 Browse Events"}
            </button>
          </div>
        )}

        {events.length > 0 && (
          <div>
            <h3 className="text-3xl font-bold text-white mb-6 text-center">
              Available Events ({events.length})
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {events.map((event) => (
                <div
                  key={event.id}
                  className="bg-white/10 backdrop-blur-md border border-white/20 rounded-xl p-6 hover:bg-white/15 transition transform hover:scale-105 shadow-xl"
                >
                  <div className="mb-4">
                    <span className="bg-purple-600 text-white text-xs px-3 py-1 rounded-full">
                      Event #{event.id}
                    </span>
                  </div>
                  
                  <h3 className="text-2xl font-bold text-white mb-3">
                    {event.name.value}
                  </h3>
                  
                  <div className="space-y-2 text-white/80 mb-4">
                    <p className="flex items-center gap-2">
                      <span>📍</span>
                      <span>{event.location.value}</span>
                    </p>
                    <p className="flex items-center gap-2">
                      <span>💰</span>
                      <span className="font-semibold">
                        {(parseInt(event.price.value) / 1000000)} STX
                      </span>
                    </p>
                    <p className="flex items-center gap-2">
                      <span>🎫</span>
                      <span>{event["total-supply"].value} tickets available</span>
                    </p>
                    <p className="flex items-center gap-2">
                      <span>✅</span>
                      <span>{event["tickets-sold"].value} sold</span>
                    </p>
                  </div>

                  <button className="w-full bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-700 hover:to-pink-700 text-white py-3 rounded-lg font-semibold transition shadow-lg">
                    Buy Ticket
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {address && events.length === 0 && !loading && (
          <div className="bg-white/10 backdrop-blur-md border border-white/20 rounded-xl p-12 text-center">
            <p className="text-white/70 text-lg mb-4">
              Click "Browse Events" to see available tickets
            </p>
          </div>
        )}

        <div className="mt-16 bg-white/5 backdrop-blur-md border border-white/10 rounded-xl p-8">
          <h3 className="text-2xl font-bold text-white mb-6 text-center">
            ✨ StacksTix Features
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="text-center">
              <div className="text-4xl mb-3">🔒</div>
              <h4 className="text-white font-semibold mb-2">Anti-Scalping</h4>
              <p className="text-white/60 text-sm">
                Built-in price caps prevent ticket scalping
              </p>
            </div>
            <div className="text-center">
              <div className="text-4xl mb-3">🎯</div>
              <h4 className="text-white font-semibold mb-2">Multi-Tier</h4>
              <p className="text-white/60 text-sm">
                VIP, GA, and Early Bird pricing options
              </p>
            </div>
            <div className="text-center">
              <div className="text-4xl mb-3">⚡</div>
              <h4 className="text-white font-semibold mb-2">Bitcoin-Secured</h4>
              <p className="text-white/60 text-sm">
                Leverages Bitcoin security via Stacks
              </p>
            </div>
          </div>
        </div>
      </main>

      <footer className="bg-black/30 backdrop-blur-md border-t border-white/10 mt-16">
        <div className="max-w-7xl mx-auto px-4 py-8 text-center text-white/60">
          <p>🚀 Built on Stacks • Live on Bitcoin Testnet</p>
          <p className="mt-2 text-sm font-mono">Contract: {contractAddress}</p>
        </div>
      </footer>
    </div>
  );
}