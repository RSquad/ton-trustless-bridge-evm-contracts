// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  // We get the contract to deploy

  // const SignatureValidator = await ethers.getContractFactory(
  //   "SignatureValidator"
  // );
  // const signatureValidator = await SignatureValidator.deploy(
  //   "0x01A740Bdd958dcDEefCB286E4cc7EE2Bcd016abb"
  // );
  // await signatureValidator.deployed();
  // console.log("signatureValidator deployed to:", signatureValidator.address);

  // const Validator = await ethers.getContractFactory("Validator");
  // const validator = await Validator.deploy(
  //   signatureValidator.address,
  //   "0xa578906c93212c6edf77041c2f4e78802a10CadB",
  //   "0xbB10dFDeB2104C1C92ce1085F1aB99D10Ba90905"
  // );
  // await validator.deployed();
  // console.log("validator deployed to:", validator.address);
  // signatureValidator.transferOwnership(validator.address);

  // const Bridge = await ethers.getContractFactory("Bridge");
  // const bridge = await Bridge.deploy(
  //   "0x01A740Bdd958dcDEefCB286E4cc7EE2Bcd016abb",
  //   "0xA4811f529DF5e794eB2D11e61157174802f56D45",
  //   "0xbB10dFDeB2104C1C92ce1085F1aB99D10Ba90905",
  //   validator.address
  // );
  // await bridge.deployed();
  // console.log("bridge deployed to:", bridge.address);

  const TreeOfCellsParser = await ethers.getContractFactory(
    "TreeOfCellsParser"
  );
  // const tocParser = await TreeOfCellsParser.attach('0xa5E2c9c2e13b858E6f13F55E83D6e00507DC4d3c');
  const tocParser = await TreeOfCellsParser.deploy();
  await tocParser.deployed();
  console.log("tocParser deployed to:", tocParser.address);
  const BlockParser = await ethers.getContractFactory("BlockParser");
  // const blockParser = await BlockParser.attach('0x53B7E6EBE6d3284B7E38082f8B5EfFBa4De0E04F')
  const blockParser = await BlockParser.deploy();
  await blockParser.deployed();
  console.log("blockParser deployed to:", blockParser.address);
  const SignatureValidator = await ethers.getContractFactory(
    "SignatureValidator"
  );
  // const signatureValidator = await SignatureValidator.attach('0xd1614C0eb3c3E2811A68c762013361e0d9F173Dc')
  const signatureValidator = await SignatureValidator.deploy(
    blockParser.address
  );
  await signatureValidator.deployed();
  console.log("signatureValidator deployed to:", signatureValidator.address);
  const ShardValidator = await ethers.getContractFactory("ShardValidator");
  // const shardValidator = await ShardValidator.attach('0x0eb0076a7cf454917EbE7e3d9a4a9a03F63A20aF');
  const shardValidator = await ShardValidator.deploy();
  await shardValidator.deployed();
  console.log("shardValidator deployed to:", shardValidator.address);
  const Validator = await ethers.getContractFactory("Validator");
  // const validator = await Validator.attach('0x6493c834Eb5E8Ea181b90a485F5aC1bA3B19b47b')
  const validator = await Validator.deploy(
    signatureValidator.address,
    shardValidator.address,
    tocParser.address
  );
  await validator.deployed();
  console.log("validator deployed to:", validator.address);
  // signatureValidator.transferOwnership(validator.address);
  const TransactionParser = await ethers.getContractFactory(
    "TransactionParser"
  );
  const transactionParser = await TransactionParser.deploy();
  await transactionParser.deployed();
  console.log("transactionParser deployed to:", transactionParser.address);
  const Token = await ethers.getContractFactory("Token");
  const token = await Token.deploy();
  await token.deployed();
  console.log("token deployed to:", token.address);
  const Bridge = await ethers.getContractFactory("Bridge");
  const bridge = await Bridge.deploy(
    blockParser.address,
    transactionParser.address,
    tocParser.address,
    // token.address,
    validator.address
  );
  await bridge.deployed();
  console.log("bridge deployed to:", bridge.address);
  const Adapter = await ethers.getContractFactory("Adapter");
  const adapter = await Adapter.deploy(
    token.address,
    transactionParser.address
  );
  await adapter.deployed();
  console.log("adapter deployed to:", adapter.address);
  adapter.transferOwnership(bridge.address);

  // const Adapter = await ethers.getContractFactory("Adapter");
  // const adapter = await Adapter.deploy(
  //   "0xC464c9065aA53A27959022eCB434dF39575764fA",
  //   "0xA4811f529DF5e794eB2D11e61157174802f56D45"
  // );
  // await adapter.deployed();
  // console.log("adapter deployed to:", adapter.address);
  // adapter.transferOwnership("0x8B77aC712ff9cd865AbfAB8E98B95f4e287cBFBB");

  // const ethers = require('ethers');

  // const eventName = "SwapEthereumInitialized(uint256,uint256)";
  // const topicId = ethers.utils.id(eventName);
  // console.log('mint', topicId);

  // const eventName2 = "SwapWTONInitialized(uint256,uint256)";
  // const topicId2 = ethers.utils.id(eventName2);
  // console.log('burn', topicId2);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
