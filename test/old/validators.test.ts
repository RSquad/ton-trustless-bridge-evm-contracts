// /* eslint-disable node/no-missing-import */
// import { expect } from "chai";
// import { BigNumber } from "ethers";
// import { ethers } from "hardhat";
// import { BlockParser, TreeOfCellsParser } from "../typechain";
// import {
//   baseBlockPart,
//   bocLeaf0,
//   bocLeaf1,
//   bocLeaf2,
//   bocLeaf3,
//   bocLeaf4,
//   bocLeaf5,
//   initialBaseBlockPart,
//   initialBocLeaf0,
//   initialBocLeaf1,
//   initialBocLeaf2,
//   initialBocLeaf3,
//   initialBocLeaf4,
//   initialBocLeaf5,
//   signature,
//   signatures,
//   testFileHash,
// } from "./data/validators_block_signatures_1";

// const emptySignature = {
//   node_id: "00",
//   r: "00",
//   s: "00",
// };

// describe("Tree of Cells parser tests", () => {
//   let treeOfCellsParser: TreeOfCellsParser;
//   let blockParser: BlockParser;

//   before(async function () {
//     const TreeOfCellsParser = await ethers.getContractFactory(
//       "TreeOfCellsParser"
//     );
//     treeOfCellsParser = await TreeOfCellsParser.deploy();

//     const BlockParser = await ethers.getContractFactory("BlockParser");
//     blockParser = await BlockParser.deploy();
//   });

//   it("init validators", async () => {
//     let boc: Buffer;
//     let bocHeader: any;
//     let toc: any;

//     boc = initialBaseBlockPart;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

//     // load block with prunned validators
//     await blockParser.parseCandidatesRootBlock(boc, bocHeader.rootIdx, toc);

//     // load validators
//     boc = initialBocLeaf0;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = initialBocLeaf1;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = initialBocLeaf2;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = initialBocLeaf3;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = initialBocLeaf4;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = initialBocLeaf5;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     let validators: any[] = await blockParser.getValidators();
//     validators = validators.filter((validator) => validator.cType !== 0);
//     let candidates: any[] = await blockParser.getCandidatesForValidators();
//     candidates = candidates.filter((validator) => validator.cType !== 0);
//     console.log(
//       validators.map((v) => ({
//         // verified: v.verified,
//         // node_id: v.node_id,
//         pub: v.pubkey,
//         weight: v.weight,
//       }))
//     );
//     // const prunned = await blockParser.getPrunedCells();
//     // console.log(prunned);
//     expect(validators.length).to.be.equal(100);
//     expect(candidates.length).to.be.equal(0);
//   });

//   it("set new validators list", async () => {
//     // verify signatures
//     for (let i = 0; i < signatures.length; i += 20) {
//       const subArr = signatures.slice(i, i + 20);
//       while (subArr.length < 20) {
//         subArr.push(signatures[0]);
//       }
//       await blockParser.verifyValidators(
//         `0x${testFileHash}`,
//         subArr.map((c) => ({
//           node_id: `0x${c.node_id}`,
//           r: `0x${c.r}`,
//           s: `0x${c.s}`,
//         })) as any[20]
//       );
//     }

//     // let currentValidators = await blockParser.getValidators();

//     // console.log(
//     //   currentValidators.map((v) => ({
//     //     // verified: v.verified,
//     //     node_id: v.node_id,
//     //   }))
//     // );
//     // console.log(
//     //   "voted validators weight:",
//     //   currentValidators
//     //     .reduce((acc, memo) => {
//     //       if (memo.verified) {
//     //         return memo.weight.add(acc);
//     //       }
//     //       return acc;
//     //     }, BigNumber.from(0))
//     //     .toString()
//     // );
//     // const totalWeight = await blockParser.getTotalWeight();
//     // console.log("total weight:", totalWeight);
//     // console.log(
//     //   "total validators weight",
//     //   currentValidators
//     //     .reduce((acc, memo) => {
//     //       return memo.weight.add(acc);
//     //     }, BigNumber.from(0))
//     //     .toString()
//     // );

//     let boc: Buffer;
//     let bocHeader: any;
//     let toc: any;

//     boc = baseBlockPart;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

//     // load block with prunned validators
//     await blockParser.parseCandidatesRootBlock(boc, bocHeader.rootIdx, toc);

//     // load validators
//     boc = bocLeaf0;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = bocLeaf1;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = bocLeaf2;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = bocLeaf3;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = bocLeaf4;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     boc = bocLeaf5;
//     bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
//     toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
//     await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);

//     let validators: any[] = await blockParser.getValidators();
//     validators = validators.filter((validator) => validator.cType !== 0);
//     let candidates: any[] = await blockParser.getCandidatesForValidators();
//     candidates = candidates.filter((validator) => validator.cType !== 0);
//     // const prunned = await blockParser.getPrunedCells();
//     // console.log(prunned);
//     expect(validators.length).to.be.equal(100);
//     expect(candidates.length).to.be.equal(0);
//   });
// });
