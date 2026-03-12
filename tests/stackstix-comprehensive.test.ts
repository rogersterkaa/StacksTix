import { describe, it, expect, beforeEach } from "vitest";
import { initSimnet } from "@hirosystems/clarinet-sdk";
import { Cl } from "@stacks/transactions";

const simnet = await initSimnet();
const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

// ============================================================
// HELPER: Set up storage contract authorization
// The logic contract must be set as owner of storage contract
// before any cross-contract calls will work
// ============================================================
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

// ============================================================
// HELPER: Create a standard test event
// ============================================================
function createTestEvent(name: string = "Test Event") {
  return simnet.callPublicFn(
    "stackstix-logic",
    "create-event",
    [
      Cl.stringUtf8(name),
      Cl.stringUtf8("Test event description"),
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


// ============================================================
// STORAGE CONTRACT TESTS
// ============================================================
describe("StacksTix - Storage Contract Tests", () => {

  it("get-next-event-id starts at 1 before any events", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-storage",
      "get-next-event-id",
      [],
      deployer
    );
    expect(result.result).toBeUint(1);
  });

  it("get-next-ticket-id starts at 1 before any tickets", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-storage",
      "get-next-ticket-id",
      [],
      deployer
    );
    expect(result.result).toBeUint(1);
  });

  it("event-exists returns false for non-existent event", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-storage",
      "event-exists",
      [Cl.uint(999)],
      deployer
    );
    expect(result.result).toBeBool(false);
  });

  it("ticket-exists returns false for non-existent ticket", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-storage",
      "ticket-exists",
      [Cl.uint(999)],
      deployer
    );
    expect(result.result).toBeBool(false);
  });

  it("get-contract-paused returns false initially", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-storage",
      "get-contract-paused",
      [],
      deployer
    );
    expect(result.result).toBeBool(false);
  });

});


// ============================================================
// LOGIC CONTRACT TESTS
// ============================================================
describe("StacksTix - Logic Contract Tests", () => {

  it("get-last-token-id returns 0 before any mints", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-last-token-id",
      [],
      deployer
    );
    expect(result.result).toBeOk(Cl.uint(0));
  });

  it("get-platform-fee-percent returns 2", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-platform-fee-percent",
      [],
      deployer
    );
    expect(result.result).toBeUint(2);
  });

  it("create-event succeeds with valid parameters", () => {
    setupContracts();
    const result = createTestEvent("Bitcoin 2026 Conference");
    expect(result.result).toBeOk(Cl.uint(1));
  });

  it("get-event-details returns data after event created", () => {
    setupContracts();
    createTestEvent("Details Test Event");

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-event-details",
      [Cl.uint(1)],
      deployer
    );
    expect(result.result).not.toBeNone();
  });

  it("get-tickets-remaining returns full supply before any sales", () => {
    setupContracts();

    simnet.callPublicFn(
      "stackstix-logic",
      "create-event",
      [
        Cl.stringUtf8("Remaining Test"),
        Cl.stringUtf8("Test"),
        Cl.stringUtf8("Anywhere"),
        Cl.uint(simnet.blockHeight + 100),
        Cl.uint(simnet.blockHeight + 200),
        Cl.uint(5000000),
          Cl.stringAscii("STX"),
          Cl.uint(30),
        Cl.bool(true),
        Cl.bool(true),
        Cl.none(),
      ],
      deployer
    );

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-tickets-remaining",
      [Cl.uint(1)],
      deployer
    );
    expect(result.result).toBeSome(Cl.uint(30));
  });

  it("is-event-organizer returns true for creator", () => {
    setupContracts();
    createTestEvent("Organizer Test");

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "is-event-organizer",
      [Cl.uint(1), Cl.principal(deployer)],
      deployer
    );
    expect(result.result).toBeBool(true);
  });

  it("is-event-organizer returns false for non-organizer", () => {
    setupContracts();
    createTestEvent("Organizer Test 2");

    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "is-event-organizer",
      [Cl.uint(1), Cl.principal(wallet1)],
      deployer
    );
    expect(result.result).toBeBool(false);
  });

  it("cancel-event succeeds when called by organizer", () => {
    setupContracts();
    createTestEvent("Cancel Me");

    const result = simnet.callPublicFn(
      "stackstix-logic",
      "cancel-event",
      [Cl.uint(1)],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));
  });

  it("cancel-event fails when called by non-organizer", () => {
    setupContracts();
    createTestEvent("Protected Event");

    const result = simnet.callPublicFn(
      "stackstix-logic",
      "cancel-event",
      [Cl.uint(1)],
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(200));
  });

});
