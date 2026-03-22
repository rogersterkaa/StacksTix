import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "StacksTix - Bitcoin NFT Ticketing",
  description: "Decentralized ticketing platform on Stacks",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
