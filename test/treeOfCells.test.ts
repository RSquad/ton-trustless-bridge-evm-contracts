import { expect } from "chai";
import { ethers } from "hardhat";
import {
  BitReader,
  BocHeaderAdapter,
  BocHeaderParser,
  TreeOfCellsParser,
} from "../typechain";
import { proofBoc3, txBoc3 } from "./data/index";

describe("Tree of Cells parser tests", () => {
  let bitReader: BitReader;
  let bocHeaderParser: BocHeaderParser;
  let treeOfCellsParser: TreeOfCellsParser;
  let bocHeaderAdapter: BocHeaderAdapter;

  before(async function () {
    const BitReader = await ethers.getContractFactory("BitReader");
    bitReader = await BitReader.deploy();

    const BocHeaderParser = await ethers.getContractFactory("BocHeaderParser", {
      libraries: {
        BitReader: bitReader.address,
      },
    });
    bocHeaderParser = await BocHeaderParser.deploy();

    const TreeOfCellsParser = await ethers.getContractFactory(
      "TreeOfCellsParser",
      {
        libraries: {
          BitReader: bitReader.address,
        },
      }
    );
    treeOfCellsParser = await TreeOfCellsParser.deploy();

    const BocHeaderAdapter = await ethers.getContractFactory(
      "BocHeaderAdapter"
    );
    bocHeaderAdapter = await BocHeaderAdapter.deploy();
  });

  //   it("check boc header", async function () {
  //     const uncheckedBocHeader = await bocHeaderParser.parseSerializedHeader(
  //       txBoc3
  //     );
  //   });

  it("check tree of cells", async function () {
    const bocHeader = await bocHeaderParser.parseSerializedHeader(txBoc3);
    const toc = await treeOfCellsParser.get_tree_of_cells(txBoc3, bocHeader);
    console.log(
      toc
        .filter((cell) => cell.cursor.gt(0))
        .map((cell, id) => ({
          id,
          cursor: cell.cursor.toNumber(),
          refs: cell.refs
            .filter((ref) => !ref.eq(255))
            .map((ref) => ref.toNumber()),
        }))
    );
  });
});
