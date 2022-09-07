import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  BitReader,
  BocHeaderAdapter,
  BocHeaderParser,
  TransactionParser,
  TreeOfCellsParser,
} from "../typechain";
import { proofBoc3, txBoc3 } from "./data/index";

describe("Tree of Cells parser tests", () => {
  let bitReader: BitReader;
  let bocHeaderParser: BocHeaderParser;
  let treeOfCellsParser: TreeOfCellsParser;
  let bocHeaderAdapter: BocHeaderAdapter;
  let transactionParser: TransactionParser;

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

    const TransactionParser = await ethers.getContractFactory(
      "TransactionParser",
      {
        libraries: {
          BitReader: bitReader.address,
        },
      }
    );
    transactionParser = await TransactionParser.deploy();
  });

  //   it("check boc header", async function () {
  //     const uncheckedBocHeader = await bocHeaderParser.parseSerializedHeader(
  //       txBoc3
  //     );
  //   });

  it("check tree of cells", async function () {
    const bocHeader = await bocHeaderParser.parseSerializedHeader(txBoc3);
    const toc = await treeOfCellsParser.get_tree_of_cells(txBoc3, bocHeader);
    const tx = await transactionParser.parseTransactionHeader(
      txBoc3,
      toc,
      bocHeader.rootIdx
    );
    // console.log(
    //   toc
    //     .filter((cell) => cell.cursor.gt(0))
    //     .map((cell, id) => ({
    //       id,
    //       cursor: cell.cursor.toNumber(),
    //       refs: cell.refs
    //         .filter((ref) => !ref.eq(255))
    //         .map((ref) => ref.toNumber()),
    //     }))
    // );
    console.log(tx);
    const bh = await bocHeaderAdapter.parse_serialized_header(txBoc3);
    const tocData = await bocHeaderAdapter.get_tree_of_cells(txBoc3, bh);
    const txData = await bocHeaderAdapter.parseTransactionHeader(
      tocData,
      '0'
    ); // await bocHeaderAdapter.deserialize(txBoc3);
    console.log(txData);
  });
});
