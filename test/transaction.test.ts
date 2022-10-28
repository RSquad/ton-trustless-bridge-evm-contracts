/* eslint-disable node/no-missing-import */
import { expect } from "chai";
import { assert } from "console";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  BlockParser,
  Bridge,
  TransactionParser,
  TreeOfCellsParser,
} from "../typechain";
import { bocProofState, masterProof } from "./data/proof";
import {
  proofTx,
  shardProof,
  signatures,
  transaction,
  validatorSet,
} from "./data/transaction";

describe("Tree of Cells parser tests", () => {
  let treeOfCellsParser: TreeOfCellsParser;
  let blockParser: BlockParser;
  let transactionParser: TransactionParser;
  let bridge: Bridge;
  let token: any;

  before(async function () {
    const TreeOfCellsParser = await ethers.getContractFactory(
      "TreeOfCellsParser"
    );
    treeOfCellsParser = await TreeOfCellsParser.deploy();

    const BlockParser = await ethers.getContractFactory("BlockParser");
    blockParser = await BlockParser.deploy();

    const TransactionParser = await ethers.getContractFactory(
      "TransactionParser"
    );
    transactionParser = await TransactionParser.deploy();

    const Token = await ethers.getContractFactory("Token");
    token = await Token.deploy();

    const Bridge = await ethers.getContractFactory("Bridge");
    bridge = await Bridge.deploy(
      blockParser.address,
      transactionParser.address,
      treeOfCellsParser.address,
      token.address
    );
  });

  it("init validators for transaction test", async () => {
    const boc = validatorSet;
    const bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    const toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

    // load block with prunned validators
    await blockParser.parseCandidatesRootBlock(boc, bocHeader.rootIdx, toc);
    await blockParser.setValidatorSet();
    // // load validators
    // boc = initialBocLeaf0;
    // bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    // toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
    // await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

    let validators: any[] = await blockParser.getValidators();
    validators = validators.filter((validator) => validator.cType !== 0);
    console.log(
      validators.map((v) => ({
        // verified: v.verified,
        // node_id: v.node_id,
        pub: v.pubkey,
        weight: v.weight,
      }))
    );
  });

  it("check main block signatures", async () => {
    await blockParser.setRootHashForValidating(
      "0x" +
        Buffer.from(
          "7yuHNSh1c3xENGt1iMt5m2ynwQ5HAVUVAm8DX+i2pcc=",
          "base64"
        ).toString("hex")
    );
    // verify signatures
    for (let i = 0; i < signatures.length; i += 20) {
      const subArr = signatures.slice(i, i + 20);
      while (subArr.length < 20) {
        subArr.push(signatures[0]);
      }
      await blockParser.verifyValidators(
        `0x${Buffer.from(
          "99APoJBFOQqo1MvRz/dQHpl9fGKrbWADrVj3iwEKbYA=",
          "base64"
        ).toString("hex")}`,
        subArr.map((c) => ({
          node_id: `0x${c.node_id}`,
          r: `0x${c.r}`,
          s: `0x${c.s}`,
        })) as any[20]
      );
    }

    await blockParser.addCurrentBlockToVerifiedSet();
  });

  it("check shard blocks", async () => {
    const boc = shardProof;
    const bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    const toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

    await blockParser.parseShardProofPath(boc, bocHeader.rootIdx, toc);
  });

  it("check transaction in block", async () => {
    let boc: Buffer;
    let bocHeader: any;
    let toc: any;

    boc = transaction;
    bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

    const transactionHeader = await transactionParser.parseTransactionHeader(
      boc,
      toc,
      bocHeader.rootIdx
    );
    const hash = toc[bocHeader.rootIdx]._hash[0];
    // console.log("input tx boc:", boc);
    console.log("hash:", hash);

    boc = proofTx;
    bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

    console.log("proof tx hash:", toc[bocHeader.rootIdx]._hash[0]);

    const isValid = await blockParser.parse_block(
      boc,
      bocHeader,
      toc,
      hash,
      transactionHeader
    );

    const isVerified = await blockParser.isVerifiedBlock(
      toc[bocHeader.rootIdx]._hash[0]
    );
    expect(isValid).to.be.equal(true);
    expect(isVerified).to.be.equal(true);
  });

  it("read data from transaction", async () => {
    const boc = transaction;
    const bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
    const toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

    const data = await transactionParser.deserializeMsgDate(
      boc,
      toc,
      bocHeader.rootIdx
    );
    console.log("Message data:");
    console.log(data);
  });

  it("bridge contract reads data from transaction", async () => {
    console.log("input tx boc:", transaction);
    await bridge.readTransaction(transaction, proofTx);
    // console.log("Message data:");
    // console.log(data);
  });

  it("state check", async () => {
    await blockParser.setVerifiedBlock(
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9",
      0
    );

    let boc = masterProof;
    let header = await treeOfCellsParser.parseSerializedHeader(boc);
    let toc = await treeOfCellsParser.get_tree_of_cells(boc, header);

    await blockParser.readMasterProof(boc, header.rootIdx, toc);

    boc = bocProofState;
    header = await treeOfCellsParser.parseSerializedHeader(boc);
    toc = await treeOfCellsParser.get_tree_of_cells(boc, header);

    await blockParser.readStateProof(
      boc,
      header.rootIdx,
      toc,
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9"
    );
  });
});
