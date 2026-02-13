import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const user1 = accounts.get("wallet_1")!;
const user2 = accounts.get("wallet_2")!;

describe("Transfer Restrictions - Anti-Scalping", () => {
  
  beforeEach(() => {
    simnet.callPublicFn(
      "stackstix-storage",
      "set-contract-owner",
      [Cl.principal(\\.stackstix-logic\)],
      deployer
    );
  });

  it("deployer can set transfer restrictions", () => {
    simnet.callPublicFn(
      "stackstix-logic",
      "create-event",
      [
        Cl.stringUtf8("Test Concert"),
        Cl.stringUtf8("A test event"),
        Cl.stringUtf8("Test Venue"),
        Cl.uint(1000),
        Cl.uint(2000),
        Cl.uint(50000000),
        Cl.uint(100),
        Cl.bool(true),
        Cl.bool(true),
        Cl.none()
      ],
      deployer
    );

    const { result } = simnet.callPublicFn(
      "stackstix-logic",
      "set-transfer-restriction",
      [
        Cl.uint(1),
        Cl.bool(true),
        Cl.some(Cl.uint(100000000)),
        Cl.none()
      ],
      deployer
    );

    expect(result).toBeOk(Cl.bool(true));
  });

  it("non-deployer cannot set restrictions", () => {
    simnet.callPublicFn(
      "stackstix-logic",
      "create-event",
      [
        Cl.stringUtf8("Test Concert"),
        Cl.stringUtf8("A test event"),
        Cl.stringUtf8("Test Venue"),
        Cl.uint(1000),
        Cl.uint(2000),
        Cl.uint(50000000),
        Cl.uint(100),
        Cl.bool(true),
        Cl.bool(true),
        Cl.none()
      ],
      deployer
    );

    const { result } = simnet.callPublicFn(
      "stackstix-logic",
      "set-transfer-restriction",
      [
        Cl.uint(1),
        Cl.bool(false),
        Cl.none(),
        Cl.none()
      ],
      user1
    );

    expect(result).toBeErr(Cl.uint(200));
  });

  it("get-transfer-restriction returns none for unrestricted ticket", () => {
    const { result } = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-transfer-restriction",
      [Cl.uint(999)],
      deployer
    );

    expect(result).toBeNone();
  });
});
