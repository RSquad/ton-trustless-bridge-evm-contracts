import { ethers } from "hardhat";
import { Validator } from "../typechain";

describe("Validator tests", () => {
  let validator: Validator;

  before(async function () {
    const TreeOfCellsParser = await ethers.getContractFactory(
      "TreeOfCellsParser"
    );
    const tocParser = await TreeOfCellsParser.deploy();

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
  });
});
