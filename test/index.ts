import { expect } from "chai";
import { assert } from "console";
import { ethers } from "hardhat";
import { proofBoc3, txBoc3 } from "./data/index";

function clearData(data: any) {
  const res = Object.entries(data).reduce((acc: any, memo: any) => {
    if (
      [
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "11",
        "12",
        "13",
        "14",
      ].includes(memo[0])
    ) {
      return acc;
    }
    acc[memo[0]] = memo[1];
    return acc;
  }, {} as any);
  return res;
}

describe("Greeter", function () {
  // it("Should deploy Adapter", async function () {
  //   const Adapter = await ethers.getContractFactory("BocHeaderAdapter");
  //   const adapter = await Adapter.deploy();

  //   const [root] = await ethers.getSigners();
  //   await adapter.deployed();

  //   // const res = await adapter.proofTx(txBoc, proofBoc);
  //   // console.log(res);

  //   // const res = await adapter.deserialize(bufBlock);
  //   // const res = await adapter.deserializeMsgData(bufBlock);
  //   // console.log("RESULT OF DESERIALIZE: ===========");
  //   // const bocHeaderInfo = await adapter.parse_serialized_header(proofBoc);
  //   // console.log("Boc Header: ============");
  //   // console.log(clearData(bocHeaderInfo));

  //   // const cells = await adapter.get_tree_of_cells(proofBoc, bocHeaderInfo);
  //   // const cells: any = res;
  //   // console.log("CELLS: ==============");
  //   // console.log(cells.filter((cell: any, idx: number) => cell.bits !== "0x"));
  //   // console.log(
  //   //   cells.filter((cell) => cell.bits !== "0x").map((cell) => cell._hash)
  //   // );

  //   // console.log("Transaction info: ==============");
  //   // console.log(clearData(res));
  //   // console.log("In Message: ==============");
  //   // console.log(clearData(res.messages.inMessage));
  //   // console.log("Out Messages: ==============");
  //   // console.log(clearData(res.messages.outMessages[0]));

  //   // const data = await adapter.deserializeMsgData(bufBlock);
  //   // console.log("Data: ==============");
  //   // console.log(clearData(data));
  //   // console.log(root.address);
  //   // const tx = await adapter.deserializeBoc(bufBlock);
  //   // console.log(tx.value);
  //   // console.log(rTx.);
  //   // console.log(bufBlock);
  // });

  it("tx root cell included in pruned block tree of cells and has same hash", async function () {
    const Adapter = await ethers.getContractFactory("BocHeaderAdapter");
    const adapter = await Adapter.deploy();

    await adapter.deployed();

    const res = await adapter.proofTx(txBoc3, proofBoc3);
    expect(res).to.be.equal(true);
  });
});
