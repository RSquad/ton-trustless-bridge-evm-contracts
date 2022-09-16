import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import nacl from "tweetnacl";
import {
  BitReader,
  BlockParser,
  BocHeaderAdapter,
  TransactionParser,
  TreeOfCellsParser,
} from "../typechain";
import { fullBlockBoc, proofBoc3, prunedFullBlockBoc, txBoc3 } from "./data/index";
import {
  decodeUTF8,
  encodeUTF8,
  encodeBase64,
  decodeBase64,
} from "tweetnacl-util";

describe("Tree of Cells parser tests", () => {
  // let bitReader: BitReader;
  // let bocHeaderParser: BocHeaderParser;
  let treeOfCellsParser: TreeOfCellsParser;
  let bocHeaderAdapter: BocHeaderAdapter;
  let transactionParser: TransactionParser;
  let blockParser: BlockParser;

  before(async function () {
    // const BitReader = await ethers.getContractFactory("BitReader");
    // bitReader = await BitReader.deploy();

    // const BocHeaderParser = await ethers.getContractFactory(
    //   "BocHeaderParser"
    // );
    // bocHeaderParser = await BocHeaderParser.deploy();

    const TreeOfCellsParser = await ethers.getContractFactory(
      "TreeOfCellsParser"
    );
    treeOfCellsParser = await TreeOfCellsParser.deploy();

    const BocHeaderAdapter = await ethers.getContractFactory(
      "BocHeaderAdapter"
    );
    bocHeaderAdapter = await BocHeaderAdapter.deploy();

    const TransactionParser = await ethers.getContractFactory(
      "TransactionParser"
    );
    transactionParser = await TransactionParser.deploy();

    const BlockParser = await ethers.getContractFactory("BlockParser");
    blockParser = await BlockParser.deploy();
  });

  //   it("check boc header", async function () {
  //     const uncheckedBocHeader = await bocHeaderParser.parseSerializedHeader(
  //       txBoc3
  //     );
  //   });

  it("check tree of cells", async function () {
    const bocHeader = await treeOfCellsParser.parseSerializedHeader(txBoc3);
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
    // console.log(tx);
    // const bh = await bocHeaderAdapter.parse_serialized_header(txBoc3);
    // const tocData = await bocHeaderAdapter.get_tree_of_cells(txBoc3, bh);
    // const txData = await bocHeaderAdapter.parseTransactionHeader(tocData, "0"); // await bocHeaderAdapter.deserialize(txBoc3);
    // console.log(txData);
  });

  it("parse block p1-p40", async function () {
    const bocHeader = await treeOfCellsParser.parseSerializedHeader(
      prunedFullBlockBoc
    );
    const toc = await treeOfCellsParser.get_tree_of_cells(
      prunedFullBlockBoc,
      bocHeader
    );
    console.log(bocHeader);
  });

  // it("nacl encrypt decrypt", async function () {
  //   const { bpublicKey, bsecretKey } = {
  //     bpublicKey: Buffer.from(
  //       "0x89D12eBB0cDcb3Fe00045c9D97D8AbFC5F6c497e",
  //       "base64"
  //     ),
  //     bsecretKey: Buffer.from(
  //       "1f09211560e1994fc21f5d101f55224ed1162ea06b7f4c57072c8128d5f842c7",
  //       "base64"
  //     ),
  //   };
  //   // const keypair = nacl.box.keyPair();

  //   const { publicKey, secretKey } = nacl.sign.keyPair();
  //   // const { publicKey, secretKey } = nacl.box.keyPair();
  //   // .fromSeed(
  //   //   // keypair.secretKey
  //   //   bsecretKey
  //   // );

  //   const uint8Message = decodeUTF8("Hello World");

  //   const nonce = nacl.randomBytes(nacl.box.nonceLength);
  //   // const sharedSecret = nacl.box.before(publicKey, secretKey);
  //   // const boxM = nacl.box.after(uint8Message, nonce, sharedSecret);

  //   const signature = nacl.sign.detached(uint8Message, secretKey);
  //   const verified = nacl.sign.detached.verify(
  //     uint8Message,
  //     signature,
  //     publicKey
  //   );

  //   console.log(Buffer.from(signature).toString("hex"), verified);

  //   const Contr = await ethers.getContractFactory("SignatureChecker");
  //   const checker = await Contr.deploy();
  //   console.log("public", Buffer.from(publicKey).toString("hex"));
  //   console.log((await ethers.getSigners())[0].address);
  //   const contractRes = await checker.checkSignature(uint8Message, {
  //     signer: "0x89D12eBB0cDcb3Fe00045c9D97D8AbFC5F6c497e", // Buffer.from(publicKey).toString("base64"),
  //     signature: signature,
  //   });

  //   console.log(contractRes);
  // });
});
