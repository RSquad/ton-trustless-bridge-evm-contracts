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
  TransactionParser,
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
  let transactionParser: TransactionParser;

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
    transactionParser = await TransactionParser.deploy();

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

    for (let i = 0; i < signatures.length; i += 5) {
      const subArr = signatures.slice(i, i + 5);
      while (subArr.length < 5) {
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
        })) as any[5]
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

    for (let i = 0; i < signatures.length; i += 5) {
      const subArr = signatures.slice(i, i + 5);
      while (subArr.length < 5) {
        subArr.push(signatures[0]);
      }

      await validator.verifyValidators(
        "0x" + rootHash,
        `0x${Buffer.from(fileHash, "hex").toString("hex")}`,
        subArr.map((c) => ({
          node_id: `0x${c.node_id}`,
          r: `0x${c.r}`,
          s: `0x${c.s}`,
        })) as any[5]
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

  // it("log test", async () => {
  //   console.log("NEED TEST");
  //   const boc =
  //     "b5ee9c72410211010002a400041011ef55aafffffffd01020304284801012f4b7524a9da9456d324d6cbf7a9971047aa656bef06e8acade2c4fb1d63a267000128480101b0722b0f81bbc633a2032c4d08e0d8c2eee5fc6d1e9be0f47730141182b53b4b0001284801016367413c77e3a363ff88eaa8bf498df5cbc060dfd1b9f80bbefbdfe311f2841c001a03894a33f6fd076913b69662d4000000000000000000000000000000000000000000000000004f1427aa9df3582bd564056e8fc00348ab7ac6e9a000bb24f78fc9d7584321c940050607284801013a2b1770037c213ff88b9bee73fd48c6a71228d6f1d91d61c39932557cb95539000828480101c5dcee397a03b5f46e8a540f2959b3b294249ad26cfac473a0aa9e3f7eff21bf00080109a0092a190a0802091004950c85090a284801015fd2ae732e8ef9c086ae35ddd1b618a55ef41bf0288ac8923601107da988f1ac0003020960e9dc0b500b0c284801010cb8033cb42bfa9a5be32ad57d6311a6c8d076598f3a02487c96a24ff75bfd89000502a3bf3f3e11530fbf01e1627567791b98f53d113cac823767e5b041503daf800c7f40d21318cb3f9f08a987df80f0b13ab3bc8dcc7a9e889e56411bb3f2d820a81ed7c0063fa14000000926b3af09033484c6340d0f03b579fcf8454c3efc078589d59de46e63d4f444f2b208dd9f96c10540f6be0031fd000000926b3af090327c7cdec27b2604eb7dfd82b4c320f226b54911636250031c3d4ac3a065377b700000926748ffa436421746b0003469098c680e0f1028480101ebba36bdd0020dcea521dcf2de4082b4c57d9688cb32fc0918ae443f742b39ef000328480101b609e30a4d88d1ae21ec71c7a4512c6f03e373ab0b2adb46cb7f24d54420707b00002848010182026f9b5c6f825773a173ff97cb7e3c992b379fe455dad679aaa63d345d8df40001b6564cc7";
  //   const txBoc =
  //     "b5ee9c7241020b010002870003b579fcf8454c3efc078589d59de46e63d4f444f2b208dd9f96c10540f6be0031fd000000926b3af090327c7cdec27b2604eb7dfd82b4c320f226b54911636250031c3d4ac3a065377b700000926748ffa436421746b0003469098c680107080201e0020401b1680101c4ec37a4a3ce9ff474924bb53f9ff6bad8bf3a33a45ecdbf2058e4ab315da50027f3e11530fbf01e1627567791b98f53d113cac823767e5b041503daf800c7f4111e1a30000622c51e0000124d675e1204c842e8d6c0030099f0a28992000000000000000000000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c80000000000000000000000000000000000000000000000000000000000000001400101df05019fe004fe7c22a61f7e03c2c4eacef23731ea7a227959046ecfcb6082a07b5f0018fe8300000000000000000000000000000000000000000000000000000000000000000100000926b3af09046421746b6006008000000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c800000000000000000000000000000000000000000000000000000000000000010082723ea9fe99fb9a6a8ed2dfbcbf60b5c99dda146e9ec0c4d3b1ebe7f9d068cf5aaafc579a23df97f5b438253724c9ca8e920f5b2d3650b186cdadd7e10ea01edeff02170464c911e1a3001865f65e11090a009e4186cc3d090000000000000000004500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc98c4c704c6263800000000000020000000000026dca495f16cfe342a0b3b52e5957d77950f02fb904e69fb1d7a2dffa54af4348409023d4e1a78ac1";

  //   // "b5ee9c7241020a0100023a0003b57acdbb697940e09b94c0dd1232ba817ee66786213116d2e3f603e2f9354886519000008f78dbe40038b5d9265a0a70f562d5ead77e9d835133dc363568338f7ff797a9ce21289e550000008f77fcbb18364188393000346734bda80106070201e0020401b1680101c4ec37a4a3ce9ff474924bb53f9ff6bad8bf3a33a45ecdbf2058e4ab315da5002b36eda5e503826e53037448caea05fb999e1884c45b4b8fd80f8be4d5221946500bebc200061ce3e4000011ef1b7c8004c8310726c0030050c0470ccf000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c80000000000004e200101df0500d7e00566ddb4bca0704dca606e89195d40bf7333c310988b6971fb01f17c9aa44328cb0000000000000000000000000000000000000000000000000000000000c0470ccf000008f78dbe4004641883931c265e5c314604b70e80431f406d438345f71e72000000000000138820008272aeb1774681c9665989520b4b0898e4d0b6edbc028f4b6291c4103ea1c9824d345e398769f5b7ee411c5662bd960125c046eb641b160d5372d8e85e180ba684d4021704474900bebc2018654c72110809009c415b4b0d4000000000000000002d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc987a1204c3d0900000000000002000000000002b64ff76122e60f00499796383371192da91c1f9ff1c26eb74f2e3c96e46e60e640501ad4f5ae2939";

  //   const header = await tocParser.parseSerializedHeader(
  //     Buffer.from(txBoc, "hex")
  //   );
  //   const toc = await tocParser.get_tree_of_cells(
  //     Buffer.from(txBoc, "hex"),
  //     header
  //   );
  //   const txHeader = await transactionParser.deserializeMsgDate(
  //     Buffer.from(txBoc, "hex"),
  //     toc,
  //     header.rootIdx
  //   );
  //   // console.log(txHeader);
  //   // console.log(toc.filter((c) => c.cursor.toNumber() !== 0));
  //   await bridge.readTransaction(
  //     Buffer.from(txBoc, "hex"),
  //     Buffer.from(boc, "hex"),
  //     adapter.address
  //   );
  // });
});
