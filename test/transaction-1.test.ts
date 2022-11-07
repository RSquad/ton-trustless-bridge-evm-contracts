import { expect } from "chai";
import { assert } from "console";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  Adapter,
  Bridge,
  SignatureValidator,
  TreeOfCellsParser,
  Validator,
} from "../typechain";
import { data } from "./data/transaction-1";

describe("Tree of Cells parser tests 1", () => {
  let bridge: Bridge;
  let validator: Validator;
  // let signatureValidator: SignatureValidator;
  let tocParser: TreeOfCellsParser;
  let adapter: Adapter;

  before(async function () {
    const TreeOfCellsParser = await ethers.getContractFactory(
      "TreeOfCellsParser"
    );
    tocParser = await TreeOfCellsParser.deploy();

    const BlockParser = await ethers.getContractFactory("BlockParser");
    const blockParser = await BlockParser.deploy();

    const SignatureValidator = await ethers.getContractFactory(
      "SignatureValidator"
    );
    const signatureValidator = await SignatureValidator.deploy(
      blockParser.address
    );

    const ShardValidator = await ethers.getContractFactory("ShardValidator");
    const shardValidator = await ShardValidator.deploy();

    const Validator = await ethers.getContractFactory("Validator");
    validator = await Validator.deploy(
      signatureValidator.address,
      shardValidator.address,
      tocParser.address
    );

    signatureValidator.transferOwnership(validator.address);

    const TransactionParser = await ethers.getContractFactory(
      "TransactionParser"
    );
    const transactionParser = await TransactionParser.deploy();

    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy();

    const Bridge = await ethers.getContractFactory("Bridge");
    bridge = await Bridge.deploy(
      blockParser.address,
      transactionParser.address,
      tocParser.address,
      // token.address,
      validator.address
    );

    const Adapter = await ethers.getContractFactory("Adapter");
    adapter = await Adapter.deploy(token.address, transactionParser.address);

    adapter.transferOwnership(bridge.address);
  });

  it("init validators", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "set-validators")!.boc[0],
      "hex"
    );

    const header = await tocParser.parseSerializedHeader(boc);
    const toc = await tocParser.get_tree_of_cells(boc, header);
    console.log(
      "root_hash:",
      toc[header.rootIdx.toNumber()]._hash[0].toString()
    );

    // console.log(
    //   toc
    //     .filter((cell: any) => cell.cursor.gt(0))
    //     .map((cell: any, id: any, a: any) => ({
    //       id,
    //       special: cell.special,
    //       cursor: cell.cursor.toNumber(),
    //       refs: cell.refs
    //         .filter((ref: any) => !ref.eq(255))
    //         .map((ref: any) => ref.toNumber()),
    //       data: boc
    //         .toString("hex")
    //         // .slice(bocHeader.data_offset.toNumber())
    //         .slice(
    //           Math.floor(cell.cursor.div(4).toNumber()),
    //           // Math.floor(cell.cursor.div(8).toNumber()) +
    //           id === 0 ? 128 : Math.floor(a[id - 1].cursor.toNumber() / 4)
    //         ),
    //       bytesStart: cell.cursor.toNumber() % 8,
    //       hash: cell._hash,
    //       depth: cell.depth,
    //       level_mask: cell.level_mask,
    //       // distance:
    //       //   id === 0
    //       //     ? 128
    //       //     : Math.floor(a[id - 1].cursor.toNumber() / 8) -
    //       //       Math.floor(cell.cursor.div(8).toNumber()),
    //     }))
    // );

    await validator.parseCandidatesRootBlock(boc);
    // const validators = await validator.getCandidatesForValidators();
    // console.log(validators.filter((validator) => validator.cType !== 0));
    // TODO: fix ownership
    await validator.setValidatorSet();
    // const validators = await validator.getValidators();
    // console.log(validators.filter((validator) => validator.cType !== 0));
  });

  it("update validators", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "proof-validators")!.boc[0],
      "hex"
    );

    const header = await tocParser.parseSerializedHeader(boc);
    const toc = await tocParser.get_tree_of_cells(boc, header);
    console.log(
      "root_hash:",
      toc[header.rootIdx.toNumber()]._hash[0].toString()
    );

    await validator.parseCandidatesRootBlock(boc);

    const signatures = data.find((el) => el.type === "proof-validators")!
      .signatures!;

    for (let i = 0; i < signatures.length; i += 20) {
      const subArr = signatures.slice(i, i + 20);
      while (subArr.length < 20) {
        subArr.push(signatures[0]);
      }

      await validator.verifyValidators(
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        `0x${Buffer.from(
          data.find((el) => el.type === "proof-validators")!.id!.fileHash,
          "hex"
        ).toString("hex")}`,
        subArr.map((c) => ({
          node_id: `0x${c.node_id}`,
          r: `0x${c.r}`,
          s: `0x${c.s}`,
        })) as any[20]
      );
    }
    // const validators = await validator.getCandidatesForValidators();
    // console.log(validators.filter((validator) => validator.cType !== 0));
    // TODO: fix ownership
    await validator.setValidatorSet();
    // const validators = await validator.getValidators();
    // console.log(validators.filter((validator) => validator.cType !== 0));
  });

  it("state-hash test", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "state-hash")!.boc as any,
      "hex"
    );
    const signatures = data.find((el) => el.type === "state-hash")?.signatures!;
    const fileHash = data.find((el) => el.type === "state-hash")?.id?.fileHash!;
    const rootHash = data.find((el) => el.type === "state-hash")?.id?.rootHash!;

    for (let i = 0; i < signatures.length; i += 20) {
      const subArr = signatures.slice(i, i + 20);
      while (subArr.length < 20) {
        subArr.push(signatures[0]);
      }

      await validator.verifyValidators(
        "0x" + rootHash,
        `0x${Buffer.from(fileHash, "hex").toString("hex")}`,
        subArr.map((c) => ({
          node_id: `0x${c.node_id}`,
          r: `0x${c.r}`,
          s: `0x${c.s}`,
        })) as any[20]
      );
    }

    await validator.addCurrentBlockToVerifiedSet("0x" + rootHash);

    console.log(
      "valid rh:",
      "0x" + rootHash,
      await validator.isVerifiedBlock("0x" + rootHash)
    );
    console.log(
      "strange test:",
      await validator.isVerifiedBlock(
        "0x" +
          "079c3097e73b3d96561e2b90230feba6108929c052b5160fe38f435e1e06cb6d"
      )
    );

    await validator.setVerifiedBlock(
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9",
      0
    );

    await validator.readMasterProof(boc);

    /* 
    

    
    tx-proof
    */
  });

  it("shard state test", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "shard-state")!.boc as any,
      "hex"
    );
    // const rootHash = data.find((el) => el.type === "state-hash")?.id?.rootHash!;

    await validator.readStateProof(
      boc,
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9"
    );
  });

  it("shard block test", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "shard-block")!.boc as any,
      "hex"
    );

    await validator.parseShardProofPath(boc);
  });

  it("bridge contract reads data from transaction", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "tx-proof")!.boc as any,
      "hex"
    );

    const txBoc = Buffer.from(
      data.find((el) => el.type === "tx-proof")!.txBoc! as any,
      "hex"
    );

    await bridge.readTransaction(txBoc, boc, adapter.address);
    // console.log("Message data:");
    // console.log(data);
  });
});
