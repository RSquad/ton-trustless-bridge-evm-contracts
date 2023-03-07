/* eslint-disable node/no-missing-import */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { assert } from "console";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  Adapter,
  Bridge,
  SignatureValidator,
  Token,
  TreeOfCellsParser,
  Validator,
} from "../typechain";
import {
  data,
  initialValidatorsBlockRootHash,
  initialValidatorsList,
  updateValidators,
  updateValidatorsRootHash,
} from "./data/transaction-1";

describe("Tree of Cells parser tests 1", () => {
  let bridge: Bridge;
  let validator: Validator;
  let tocParser: TreeOfCellsParser;
  let adapter: Adapter;
  let token: Token;

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
    token = await Token.deploy();

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

  it("Should throw an error when use wrong boc for parseCandidatesRootBlock", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "state-hash")!.boc[0],
      "hex"
    );

    try {
      await validator.parseCandidatesRootBlock(boc);
      assert(false);
    } catch (error) {
      assert(true);
    }
  });

  it("Should add validators from boc to candidatesForValidators", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "set-validators")!.boc[0],
      "hex"
    );

    await validator.parseCandidatesRootBlock(boc);

    const validators = (await validator.getCandidatesForValidators()).filter(
      (validator) => validator.cType !== 0
    );

    validators.forEach((validator) => {
      const item = initialValidatorsList.find(
        (v) => v.node_id === validator.node_id
      );
      expect(item, "added some wrong candidate for validators").to.be.not.equal(
        undefined
      );
      expect(validator.pubkey, "incorrect pubkey in contract").to.be.equal(
        item?.pubkey
      );
    });
  });

  // TODO: onlyOwner test

  it("Should set initial validators and its block's hash", async () => {
    await validator.initValidators();
    let validators = (await validator.getValidators()).filter(
      (validator) => validator.cType !== 0
    );

    expect(
      await validator.isVerifiedBlock(initialValidatorsBlockRootHash),
      "validators block should be valid after save validators"
    ).to.be.equal(true);

    validators.forEach((validator) => {
      const item = initialValidatorsList.find(
        (v) => v.node_id === validator.node_id
      );
      expect(item, "added some wrong candidate for validators").to.be.not.equal(
        undefined
      );
      expect(validator.pubkey, "incorrect pubkey in contract").to.be.equal(
        item?.pubkey
      );
    });

    validators = (await validator.getCandidatesForValidators()).filter(
      (validator) => validator.cType !== 0
    );

    expect(
      validators.length,
      "candidates list should be empty after save validators"
    ).to.be.equal(0);
  });

  it("Should add validators for update from boc to candidatesForValidators", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "proof-validators")!.boc[0],
      "hex"
    );

    await validator.parseCandidatesRootBlock(boc);

    const validators = (await validator.getCandidatesForValidators()).filter(
      (validator) => validator.cType !== 0
    );

    validators.forEach((validator) => {
      const item = updateValidators.find(
        (v) => v.node_id === validator.node_id
      );
      expect(item, "added some wrong candidate for validators").to.be.not.equal(
        undefined
      );
      expect(validator.pubkey, "incorrect pubkey in contract").to.be.equal(
        item?.pubkey
      );
    });
  });

  it("Should throw an exception for set validators when signatures was not checked", async () => {
    try {
      await validator.setValidatorSet();
      assert(false);
    } catch (error) {
      assert(true);
    }
  });

  // TODO: check signatures for wrong boc/fileHash/vdata

  it("Should verify signatures", async () => {
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

    for (let i = 0; i < signatures.length; i++) {
      expect(
        await validator.isSignedByValidator(
          "0x" + signatures[i].node_id,
          updateValidatorsRootHash
        )
      ).to.be.equal(true);
    }
  });

  it("should update validators", async () => {
    await validator.setValidatorSet();
    let validators = (await validator.getValidators()).filter(
      (validator) => validator.cType !== 0
    );

    expect(
      await validator.isVerifiedBlock(updateValidatorsRootHash),
      "validators block should be valid after save validators"
    ).to.be.equal(true);

    validators.forEach((validator) => {
      const item = updateValidators.find(
        (v) => v.node_id === validator.node_id
      );
      expect(item, "added some wrong candidate for validators").to.be.not.equal(
        undefined
      );
      expect(validator.pubkey, "incorrect pubkey in contract").to.be.equal(
        item?.pubkey
      );
    });

    validators = (await validator.getCandidatesForValidators()).filter(
      (validator) => validator.cType !== 0
    );

    expect(
      validators.length,
      "candidates list should be empty after save validators"
    ).to.be.equal(0);
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

    await validator.setVerifiedBlock(
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9",
      0
    );

    expect(
      await validator.isVerifiedBlock(
        "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9"
      )
    ).to.be.equal(true);

    await validator.readMasterProof(boc);
    // TODO: add check for new_hash
  });

  it("shard state test", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "shard-state")!.boc as any,
      "hex"
    );

    await validator.readStateProof(
      boc,
      "0x456ae983e2af89959179ed8b0e47ab702f06addef7022cb6c365aac4b0e5a0b9"
    );

    expect(
      await validator.isVerifiedBlock(
        "0xef2b87352875737c44346b7588cb799b6ca7c10e47015515026f035fe8b6a5c7"
      )
    ).to.be.equal(true);
  });

  it("shard block test", async () => {
    const boc = Buffer.from(
      data.find((el) => el.type === "shard-block")!.boc as any,
      "hex"
    );

    await validator.parseShardProofPath(boc);
    expect(
      await validator.isVerifiedBlock(
        "0x641ccceabf2d7944f87e7c7d0e5de8c5e00b890044cc6d21ce14103becc6196a"
      )
    ).to.be.equal(true);
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

    expect(
      await token.balanceOf("0xe003de6861c9e3b82f293335d4cdf90c299cbbd3")
    ).to.be.equal("12733090031156665196");
  });
});
