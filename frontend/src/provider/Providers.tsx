"use client";

import { RainbowKitProvider, lightTheme } from "@rainbow-me/rainbowkit";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { wagmiConfig } from "@/config/wagmi";
import "@rainbow-me/rainbowkit/styles.css";

const queryClient = new QueryClient();

const rkTheme = lightTheme({
  accentColor: "#E11D48",
  accentColorForeground: "#ffffff",
  borderRadius: "large",
  fontStack: "system",
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider modalSize="compact" theme={rkTheme}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
