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

  const TreeOfCellsParser = await ethers.getContractFactory(
    "TreeOfCellsParser"
  );
  const tocParser = await TreeOfCellsParser.deploy();
  await tocParser.deployed();
  console.log("tocParser deployed to:", tocParser.address);

  const BlockParser = await ethers.getContractFactory("BlockParser");
  const blockParser = await BlockParser.deploy();
  await blockParser.deployed();

  console.log("blockParser deployed to:", blockParser.address);

  const SignatureValidator = await ethers.getContractFactory(
    "SignatureValidator"
  );
  const signatureValidator = await SignatureValidator.deploy(
    blockParser.address
  );
  await signatureValidator.deployed();

  console.log("signatureValidator deployed to:", signatureValidator.address);

  const ShardValidator = await ethers.getContractFactory("ShardValidator");
  const shardValidator = await ShardValidator.deploy();
  await shardValidator.deployed();
  console.log("shardValidator deployed to:", shardValidator.address);

  const Validator = await ethers.getContractFactory("Validator");
  const validator = await Validator.deploy(
    signatureValidator.address,
    shardValidator.address,
    tocParser.address
  );
  await validator.deployed();
  console.log("validator deployed to:", validator.address);

  signatureValidator.transferOwnership(validator.address);

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

  // console.log(await validator.getValidators());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
