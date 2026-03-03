import { describe, it, expect } from "vitest";
import { initSimnet } from "@hirosystems/clarinet-sdk";
import { Cl } from "@stacks/transactions";

const simnet = await initSimnet();
const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;

describe("Transfer Restrictions Tests", () => {

  it("deployer can set transfer restriction", () => {
    const result = simnet.callPublicFn(
      "stackstix-logic",
      "set-transfer-restriction",
      [
        Cl.uint(1),
        Cl.bool(true),
        Cl.some(Cl.uint(150000000)),
        Cl.none(),
      ],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));
  });

  it("non-deployer cannot set transfer restriction", () => {
    const wallet1 = accounts.get("wallet_1")!;
    const result = simnet.callPublicFn(
      "stackstix-logic",
      "set-transfer-restriction",
      [
        Cl.uint(1),
        Cl.bool(false),
        Cl.none(),
        Cl.none(),
      ],
      wallet1
    );
    expect(result.result).toBeErr(Cl.uint(200));
  });

  it("get-transfer-restriction returns none for unrestricted ticket", () => {
    const result = simnet.callReadOnlyFn(
      "stackstix-logic",
      "get-transfer-restriction",
      [Cl.uint(999)],
      deployer
    );
    expect(result.result).toBeNone();
  });

});
