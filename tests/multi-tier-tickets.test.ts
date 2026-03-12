import { describe, it, expect } from "vitest";
import { initSimnet } from "@hirosystems/clarinet-sdk";
import { Cl } from "@stacks/transactions";

const simnet = await initSimnet();
const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;

// Helper: Set up contracts
function setupContracts() {
  const logicContractPrincipal = `${deployer}.stackstix-logic`;
  simnet.callPublicFn(
    "stackstix-storage",
    "set-contract-owner",
    [Cl.principal(logicContractPrincipal)],
    deployer
  );

  const storageContractPrincipal = `${deployer}.stackstix-storage`;
  simnet.callPublicFn(
    "stackstix-logic",
    "set-storage-contract",
    [Cl.principal(storageContractPrincipal)],
    deployer
  );
}

// Helper: Create test event
function createTestEvent(name = "Test Event") {
  return simnet.callPublicFn(
    "stackstix-logic",
    "create-event",
    [
      Cl.stringUtf8(name),
      Cl.stringUtf8("Test description"),
      Cl.stringUtf8("Lagos, Nigeria"),
      Cl.uint(simnet.blockHeight + 100),
      Cl.uint(simnet.blockHeight + 200),
      Cl.uint(50000000),
        Cl.stringAscii("STX"),
        Cl.uint(100),
        Cl.bool(true),
      Cl.bool(true),
      Cl.none(),
    ],
    deployer
  );
}

describe("Multi-Tier Ticket System", () => {

  it("organizer can create VIP tier", () => {
    setupContracts();
    createTestEvent("Concert");

    const result = simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("VIP"),
        Cl.uint(100000000),
        Cl.uint(50),
        Cl.stringUtf8("Backstage access + Meet & Greet"),
      ],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));
  });

  it("non-organizer cannot create tier", () => {
    setupContracts();
    createTestEvent("Concert");

    const result = simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("VIP"),
        Cl.uint(100000000),
        Cl.uint(50),
        Cl.stringUtf8("Backstage access"),
      ],
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(200));
  });

  it("can purchase ticket from VIP tier", () => {
    setupContracts();
    createTestEvent("Concert");

    simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("VIP"),
        Cl.uint(100000000),
        Cl.uint(50),
        Cl.stringUtf8("Backstage access"),
      ],
      deployer
    );

    const result = simnet.callPublicFn(
      "stackstix-logic",
      "purchase-tiered-ticket",
      [Cl.uint(1), Cl.stringAscii("VIP")],
      wallet1
    );
    expect(result.result).toBeOk(Cl.uint(1));
  });

  it("get-tier-details returns tier info", () => {
    setupContracts();
    createTestEvent("Concert");

    simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("VIP"),
        Cl.uint(100000000),
        Cl.uint(50),
        Cl.stringUtf8("Backstage access"),
      ],
      deployer
    );

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-tier-details",
      [Cl.uint(1), Cl.stringAscii("VIP")],
      deployer
    );
    expect(result.result).toBeSome(
  Cl.tuple({
    price: Cl.uint(100000000),
    "total-supply": Cl.uint(50),
    "tickets-sold": Cl.uint(0),
    benefits: Cl.stringUtf8("Backstage access"),
    "is-active": Cl.bool(true),
  })
);
  });

  it("get-tier-tickets-remaining shows correct count", () => {
    setupContracts();
    createTestEvent("Concert");

    simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("GA"),
        Cl.uint(50000000),
        Cl.uint(30),
        Cl.stringUtf8("General admission"),
      ],
      deployer
    );

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-tier-tickets-remaining",
      [Cl.uint(1), Cl.stringAscii("GA")],
      deployer
    );
    expect(result.result).toBeSome(Cl.uint(30));
  });

  it("tier sold count increments after purchase", () => {
    setupContracts();
    createTestEvent("Concert");

    simnet.callPublicFn(
      "stackstix-logic",
      "create-ticket-tier",
      [
        Cl.uint(1),
        Cl.stringAscii("GA"),
        Cl.uint(50000000),
        Cl.uint(30),
        Cl.stringUtf8("General admission"),
      ],
      deployer
    );

    simnet.callPublicFn(
      "stackstix-logic",
      "purchase-tiered-ticket",
      [Cl.uint(1), Cl.stringAscii("GA")],
      wallet1
    );

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-tier-tickets-remaining",
      [Cl.uint(1), Cl.stringAscii("GA")],
      deployer
    );
    expect(result.result).toBeSome(Cl.uint(29));
  });

});
