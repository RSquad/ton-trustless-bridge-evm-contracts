import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import nacl from "tweetnacl";
import {
  BitReader,
  BlockParser,
  BocHeaderAdapter,
  TestEd25519,
  TransactionParser,
  TreeOfCellsParser,
} from "../typechain";
import {
  fullBlockBoc,
  proofBoc3,
  proofOldValidatorSetBoc,
  proofValidatorSetBoc,
  prunedFullBlockBoc,
  txBoc3,
} from "./data/index";
import {
  decodeUTF8,
  encodeUTF8,
  encodeBase64,
  decodeBase64,
} from "tweetnacl-util";

const signature =
  "706e0bc54b36c905aaacd2759c71ffb04a326ef6a8957bedc2c0e59f549fbc1faf14f0a091c01c1569e5bad47fe0be72fdba7c1c5af51b147eb3b94e9eb75db50d01c0c4";

const cheks = [
  {
    node_id: "70dd4d789f7a18b09d1c3533c8406db62ae91ea7adb6e53cbeab030b874764a9",
    r: "f640c50b0e2d26097f61e8691bee6f7ac3424e7f9af0252efbb1d062a583d58d",
    s: "a7885894f40c258e89189732b693fa61c65650cbdc6796de4e2bacc569bdc109",
  },
  {
    node_id: "e2bf471f2b6200a8f30fb667c670cab466ca66fa469014cb0986da9c7a32a1b2",
    r: "7bbbaa2f8a9fa3841b9aaed747b9a853b1f8031b3583cfd1dba81b248fb13c21",
    s: "2c86fbffea4c2e484198f2a181db7134413d100a6dc4057bf1557e6423e3900b",
  },
  {
    node_id: "4cbd1d794ca0fa455fb2cfa3e11813146871c907c2eccf175e3e6fdb8391aef3",
    r: "a975696488d48d2eda1a7f651771f62ce5978b2bcffd7ac51919f5fb2ed597bd",
    s: "c7d8c59a53078e3957471d9343d51d3d5e0429bfdda0ac82169a8d5ec931d60b",
  },
  {
    node_id: "2d2ff14aef69f50b8807abd127729d37fa3d258e8259c731a3c9fb6829c4f840",
    r: "29849e1979d1cb0e08404a7cfecba65250e91840dc0675f29263ca99e95a55f4",
    s: "e41b66e0f1ba291e967e0b0cb9d8d8e239c0a8c61392d7cff6bc0cd33ab2cc08",
  },
  {
    node_id: "8f36a47727ce9164371748076cb194bff370338be4603fe20b2b39d5b5b4d91d",
    r: "babb45574d181800697687d40ecac3f59148484dca95274c44c6f4ec0e4cc7fe",
    s: "79563a6d3a7645a21c04b1067128d23370bbcd4a9cc685e3e72d000d3ca4530a",
  },
  {
    node_id: "dc7b8ff56650da77f1dbca07cebb0681f00fbd206fc618299cea75c03c6ac50f",
    r: "bd43c7a1afa4f5186405f39d4f70e65b0977b4acb130c474851e1df32f3d1957",
    s: "af6e2ee26f1060979127b6cd0c6e73b698a067f848ea1c2f242e03a4c69fe20f",
  },
  {
    node_id: "2993da4123b2b7741179f1b88cb63a9ecd25ed5d95f398cb3bb3994214bc4bf0",
    r: "694f6bfc0b26038ca54bc17e0046e8e310ceb2dd4443ee1fd6d2ead9174b3bfd",
    s: "4acbfbe728270716b29a3da9f376369da2579217316d793d1584944a17a4af08",
  },
  {
    node_id: "350969cd0bed53afe6dda113aab5123d61fc83eff7bdbb387d86714dd68c6680",
    r: "9e7190e89281e6e424838db2deeb860d3d3b12f2da1ef07adde21d12baf6b0a9",
    s: "e7684afae14f8ca23e36d76ec9703a6c7921fb883b975b4cfd54c8e9f1cd2801",
  },
  {
    node_id: "b4ad91e6b8dd378ed7e502718156fa99af218964b11286e6b87fa2d2ab479ff0",
    r: "077df972af41d488d9d7fa7ec1238107d33c598c7cec5d0a4fe005534fdc99a7",
    s: "5b51c7d8ca358a8657053b4abcde919f1d8737616941ae9d26fa107f7a289c0c",
  },
  {
    node_id: "f6eec0123be4d8ba2570934ac2f39febf22b817933370787539dba7019398bd5",
    r: "0dc326c064598832a87cdfbe879dd32a1c2cce536267308f855e904bc8b994fa",
    s: "7fd2d270d014c40202bf2914f22e690e41ad9b54cf8a4827993c864a72e93508",
  },
  {
    node_id: "1449959286ce76b6fd3f5f0d0628061dead4d4d2faf1ac3c796733fc24bc9b05",
    r: "c052dd959e56ebfd3806e442f843db32e5f5c3365a5a2e9509a763169a20cf13",
    s: "fdf450fa042883a62bf0ef909381f6d28f0c520a49262a5479eaa2580541ac07",
  },
  {
    node_id: "31837eaa29cbabb8e0bb21b8e2338f6056ce2d5cdfc20de0898540a71c8ae628",
    r: "d1d4d2f6d942eb781637adae08717355b796ac5159b192bfe6320e59eeb64eb7",
    s: "5a728895c11d2fd99b7b69ab9db5b1705391a93338841d66d42cd23aa2ff4202",
  },
  {
    node_id: "123926f39dbece9d90deb1e017b46595cf0ec8c58ae38e4160d42b7e183232c7",
    r: "35fe2417172d983f9c17621d0b8fb737190432df7e67463c76502299a5d6302c",
    s: "47e55f25cdb332acd67f818aa6759e90ad694b995fc06b5129f290e9bdcb5e00",
  },
  {
    node_id: "5c30cafa5b15b654bca6ef46dca708e50955ba6d9223a2655322ca90444ecbcd",
    r: "c42900fc4cc3535ad9e5dc83462f5a5d2e6c7928916d8f1dfd0f0282fee880f2",
    s: "624e8de6327f214a0405515a21ba8367022e5a0fd4eb303e5414acbba44b1806",
  },
  {
    node_id: "b0dbdfac489577b06a750a166d03491fe93fca5f86ced84940551c6c681d9bb0",
    r: "7ec93ee3e71d11a811fcd3d28667516a284f0fc10c4f942fc460bffda67b52e9",
    s: "9333086371cd32699a983d465292faf5526b9527023de195357b175296c33907",
  },
  {
    node_id: "d7d9ce1d64b6b41af3f40359e2273427e263f22e04d2246ed2a3e85732d8f83c",
    r: "ab2fd1f060d4d53fd309e1818d2cbfb4048312db6bb26b98bd0d527c35b45446",
    s: "9ea96ed08926e6a33cc6d9e50f1e2865314ec5038c91d6e39a99eecd2be9cc04",
  },
  {
    node_id: "180c265403a197ef2f89e6b3bf0697844e157b6148452be96ebf22f999d2a9b3",
    r: "93b81639d8a9884126a9bd4552c48c4138b258a7cb1c8d60135c9d0681b112be",
    s: "3c4cdd86f5e70c48ea861a3fc1ab74395696d4e212d473c57f3a6c119958ee06",
  },
  {
    node_id: "4cfd04784461caf629475c113231b0ce7b12aaee55a6548425fef145c491d6da",
    r: "a9e3710570dfa3466752cd0f8e7af462ee2459c1f033d4fe3dbb0e35c9d7c94e",
    s: "41532f4be0b8b8f4256234b730b0669e4e36a7115ecf69a1619873826f4d4509",
  },
  {
    node_id: "9b6e1db63c6990ed62dd0eea80a2704d61f674115f35c53574d17a18b554c1cc",
    r: "872cc77e042d6172c615bdc97da05325d05bb5c3e56856ceb2427d2a84d40be7",
    s: "4ac09bbf4c07d4b2deae44f4ddfc9152b19d662ce44696c34f055d1fe7474b02",
  },
  {
    node_id: "309359bfc1b4a66705419aeb7801407810700aa1abafaab7e2ddadd3e99aa362",
    r: "88429845e5d069329221b4ea12b7f02903e6a87691506dfc06a16a5cb6ace6ef",
    s: "9ca808d5f11f2d539ae45b281a4b67f43791040940577d5b8f8eed26b8b92d00",
  },
  {
    node_id: "7132cd07d943304763caef931cdef7d776d38ce59931b8bd7f98d46fbc5a4ab4",
    r: "3452a0817fc1a47d2bc57cce34e4563b72d65dd3f397c9d807d4893a59b3d05a",
    s: "032924ad5f4bf625a6299a63578921692cf0f0ce2a33ae3e6f480e25f7b2710d",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },

  // for tests
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
  {
    node_id: "7585bc6bc89e417b7a060f659d462330035f10839b66eda6c99e9236a6bb6715",
    r: "892ddccc9fa72428480177acb92f753f7763962323d4206c2ccd45ee2f192449",
    s: "26de00a470b1c6ec295981202c3cdfeaee3045624db85298d613258bc426b20e",
  },
];

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

    const ed25519Factory = await ethers.getContractFactory("Ed25519");
    const ed25519 = await ed25519Factory.deploy();

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

    const BlockParser = await ethers.getContractFactory("BlockParser", {
      // libraries: {
      //   Ed25519: ed25519.address,
      // },
    });
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
      proofOldValidatorSetBoc
    );
    const toc = await treeOfCellsParser.get_tree_of_cells(
      proofOldValidatorSetBoc,
      bocHeader
    );
    // config param p34;
    console.log(
      toc
        .filter((cell) => cell.cursor.gt(0))
        .map((cell, id) => ({
          id,
          special: cell.special,
          cursor: cell.cursor.toNumber(),
          refs: cell.refs
            .filter((ref) => !ref.eq(255))
            .map((ref) => ref.toNumber()),
        }))
    );
    console.log(bocHeader.rootIdx);
    // const parsed = await blockParser.parse_block(
    await blockParser.setValidatorSet(
      proofOldValidatorSetBoc,
      bocHeader.rootIdx,
      toc
    );

    // console.log("checks:", cheks.length);
    // console.log("start verify. data:");
    // console.log(`0x${signature}`);
    // console.log({...check})
    await blockParser.verifyValidators(
      `0x${signature}`,
      cheks.map((c) => ({
        node_id: `0x${c.node_id}`,
        r: `0x${c.r}`,
        s: `0x${c.s}`,
      })) as any
    );

    await blockParser.setValidatorSet(
      proofOldValidatorSetBoc,
      bocHeader.rootIdx,
      toc
    );

    // const ed25519Factory = await ethers.getContractFactory("TestEd25519");
    // const ed25519 = (await ed25519Factory.deploy()) as TestEd25519;

    const parsed = await blockParser.getValidators();
    console.log(parsed);

    // for (let i = 1; i < cheks.length; i++) {
    //   const validator = parsed.find((v) => {
    //     return v.node_id === "0x" + cheks[i].node_id;
    //   });
    //   if (!validator) {
    //     console.log("validator not found");
    //     return;
    //   }

    //   console.log("test", i, cheks[i].node_id);
    //   console.log("args: =========");
    //   console.log(
    //     validator.pubkey,
    //     `0x${cheks[i].r}`,
    //     `0x${cheks[i].s}`,
    //     `0x${signature}`
    //   );
    //   const val = await ed25519.verify(
    //     validator.pubkey,
    //     `0x${cheks[i].r}`,
    //     `0x${cheks[i].s}`,
    //     `0x${signature}`
    //   );
    //   expect(true).to.eq(val);
    // }
    // set validator list from boc1

    // boc2 get validator set
    // get node_ids for validators from boc2
    // check signature (ED25519)
    // set new list of validators
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
