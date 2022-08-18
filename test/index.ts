import { expect } from "chai";
import { assert } from "console";
import { ethers } from "hardhat";

const transactionBoc =
  "te6ccgECBgEAATMAA69wT2TGr7/z3RDYumcHeQrJZw1UDzepRIsDN7qmpakqysAAAZPhlKz8HrdGqXwTzwHL0QzNokz2/vEXtdYn3Gz7uPMCxnJJNKbQAAGT4ZLEtDYq8lBgABQIBQQBAgUgMDQDAgBpYAAAAJYAAAAEAAYAAAAAAAUZroTxe4+LIgJql1/1Xxqxn95KdodE0heN+mO7Uz4QekCQJrwAoEJmUBfXhAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyYT3gP0OlPbej0/Uptb3fv84uqQK9d6qfFHr4pi0ljvfDTQLN9rCtqTl05OkkT2OGuBCYi2ff56pewZCPdRJ20QABIA==";
const transactionBoc2 =
  "te6ccgECCQEAAggAA69zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzAAAVmmVRs0bhDnvty2SgMYKHnFbUgoV8Nr1YJcb3sESwZ6mm/RExsgAAFZplUbNEYg39EwADQIBQQBAg8ECQ7msoAYEQMCAGHAAAAAAAACAAAAAAACWOOfKpej3EtC+yA1UolLQuFB8LCOeI+CjSJB6Kd9tCZAUBlMAJ5CXSwGGoAAAAAAAAAAAFcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyKzPfy+2K1dlWcVuYEIqpRje+lsy2BCHs8UEmDmneNb3ugdjvxThV9GlIPPeNUCsTYmzbh4j5k95Zth3tcB0IBgIB4AgGAQHfBwDLaf5mZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZz/YBmy7sqO7h7E0J0dyfdvUBrL5r3QtiseRrYuOzWVNghDuaygAAAAAKzTKo2aOxBv6Jn////8AAAAAAAAA+iOyuhJAAMlp/sAzZd2VHdw9iaE6O5Pu3qA1l817oWxWPI1sXHZrKmwRP8zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM0O5rKAAGy3O8AAArNMqjZojEG/omI7K6EgAAAAAAAAD6QA==";

const transaction3 =
  "te6cckECCQEAAjQAA7V5pN7rmQqe6px52pJdNa+SpyE0tbr8NMpvO0dtBWmJJVAAABpz1SwgO2pcsB7JSduXdX6YNLwH3tIspRC7x3SB5Ag3XHiYQImwAAAaclASwBYtAOmQADRndEUoAQIDAgHgBAUAgnLJtfkbpCwPnLxnDFheAoibKFxVT8r+hV3gR4ilSusnSUJzCR093T7s5r1s0EZmK6T2A4EQ7L27c6BLhEPUb1rlAhcEYkkO5rKAGGWL7BEHCAD5aAD4LoURgpbQwrJthc56KoxE1O8oBKjV5T5mOUvKIMtcMQAmk3uuZCp7qnHnakl01r5KnITS1uvw0ym87R20FaYklVDuaygABhRYYAAAA056pYQExaAdMgAAAAAAAAA9gIEBggKDA4QEhQWGBocHgIEBggKAAAAAAAAYHMABAd8GANfgBNJvdcyFT3VOPO1JLprXyVOQmlrdfhplN52jtoK0xJKrAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADARwzPAAABpz1SwgRi0A6ZAECAwQFBgcICQoLDA0ODwECAwQFAAAAAAAAMDmAAnkFrjD0JAAAAAAAAAAAAKgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAb8mHoSBMPQkAAAAAAAACAAAAAAADpn9fPgzYhDtiiWUBxLvx0ZlJvlQMDOuIa4wbq3hjrjBAUBrUpi0+TQ==";
const transaction4 =
  "te6cckECCQEAAjYAA7V5pN7rmQqe6px52pJdNa+SpyE0tbr8NMpvO0dtBWmJJVAAAB1t2SlAMYwqtaKxPP7OJVWznScECB1XSqneZAsTkGPJgcYAjJ+AAAAac9UsIDYtgNXAADRnl1yoAQIDAgHgBAUAgnJCcwkdPd0+7Oa9bNBGZiuk9gOBEOy9u3OgS4RD1G9a5Qno4eh1FJtFCFy5XznwHcEFDRkr7vCRkktQb/A2LngsAhsEwEZRSQF9eEAYZYvsEQcIAPloAPguhRGCltDCsm2FznoqjETU7ygEqNXlPmY5S8ogy1wxACaTe65kKnuqcedqSXTWvkqchNLW6/DTKbztHbQVpiSVUBfXhAAGFFhgAAADrbslKATFsBq4AAAAAAAAAD2AgQGCAoMDhASFBYYGhweAgQGCAoAAAAAAABgcwAEB3wYA1+AE0m91zIVPdU487UkumtfJU5CaWt1+GmU3naO2grTEkqsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMBHDM8AAAHW3ZKUBGLYDVwAQIDBAUGBwgJCgsMDQ4PAQIDBAUAAAAAAAAwOYACeQWuMBhqAAAAAAAAAAAAqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABvyYehIEw9CQAAAAAAAAIAAAAAAAOmf18+DNiEO2KJZQHEu/HRmUm+VAwM64hrjBureGOuMEBQGtQ2ZS+F";
const transaction5 =
  "te6cckECCQEAAjUAA7V5pN7rmQqe6px52pJdNa+SpyE0tbr8NMpvO0dtBWmJJVAAAB1yoLmsNz3WJ/whc1hPnszLvnZo5ScW6H9j1x385t8dKqKXa2lwAAAdbdkpQDYtgZqwADRndGpIAQIDAgHgBAUAgnIJ6OHodRSbRQhcuV858B3BBQ0ZK+7wkZJLUG/wNi54LJ7KrvmFAYHZPtE2v6a5u79Jl5IJvLLYs5QqT4/LBjEYAhkEgGyJAX14QBhli+wRBwgA+WgA+C6FEYKW0MKybYXOeiqMRNTvKASo1eU+ZjlLyiDLXDEAJpN7rmQqe6px52pJdNa+SpyE0tbr8NMpvO0dtBWmJJVQF9eEAAYUWGAAAAOuVBc1hMWwM1YAAAAAAAAAPfnP63KNVsR7emc1XEE5POf/3JEzAAAAAAJiWgBAAQHfBgDX4ATSb3XMhU91TjztSS6a18lTkJpa3X4aZTedo7aCtMSSqwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwEcMzwAAAdcqC5rEYtgZqzzn9blGq2I9vTOariCcnnP/7kiZgAAAAAExLQAgAJ5Ba4wGGoAAAAAAAAAAACoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAG/Jh6EgTD0JAAAAAAAAAgAAAAAAA2xX0KDL4VOGX/xtMxVkXuuX/gEgxqZIEiRwvLcKZ2s8QFAa1EVU64k=";

const transactionForProof1 = "te6ccgECCQEAAgcAA69zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzAAAVmmVRs0RdyHw+NMfP3sO18j6cvVGeSGfxRPuHrU8XLC8iyV17+QAAFZplUbNCYg39EwADQIBQQBAg8ECQ7msoAYEQMCAGHAAAAAAAACAAAAAAACeTJrgIVKy0LIY0Q8rSyWc9a79CknNcWKgxD8TRM41q5AUBkMAJ5EoGwGGoAAAAAAAAAAAFcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyUeQRc8cUEyw7tZAoiT/+ee3SQz9qZPPA6E2ThIiqlfkrM9/L7YrV2VZxW5gQiqlGN76WzLYEIezxQSYOad41vQIB4AgGAQHfBwDJaf5mZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZz/MQYF72fNrkD5l7GYf6+WfHPYvu6zII7/G3z/w3qGk9VwGTRiDSHWgAAAAKzTKo2aKxBv6Jny3uZIAAAAAAAAA+cAAyWn+YgwL3s+bXIHzL2Mw/18s+Oexfd1mQR3+Nvn/hvUNJ6s/zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzQ7msoAAbLc7wAACs0yqNmhsQb+iYjsroSAAAAAAAAAPnA";
const transactionForProof2 = "te6ccgECCgEAAj8AA7d7OuqCGlYnbpJfPpxxgp6X20daSjzWT0i5iNiOgVFnAIAAAafMwCw0PszFvnhjWQYNCNMKPnfsIoCoGt7VRNC8hTNm0usAF1zwAAGnbxq1LJYug9nQADSAv8GXSAUEAQIfBQB2dGoJED4FIBiAfivOEQMCAG/JzEtATMtyiAAAAAAAAgAAAAAAA0FirgC2aIXrlD73SpqFHWjnFGcG6WU1/nIyYzTVlx40QFAZDACeQzrsBqcgAAAAAAAAAACdAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACCcpc2N4V5hGLOulaz6wVRP3oBBdc1IV2lcJrIQ+6zM43OPymQVpoUr62xy+jTQqD4wW2hiFLjQQYyeb4K3Ekx+ZUCAeAIBgEB3wcAyWn/Z11QQ0rE7dJL59OOMFPS+2jrSUeayekXMRsR0Cos4BE/zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzQ7msoAAbLc7wAADT5mAWGiMXQezojsroSAAAAAAAAAUZAAbFoAaf6IyaucIuL6xYicxjDECFpxLzJej7Z+wZAGiOzjEGZP+zrqghpWJ26SXz6ccYKel9tHWko81k9IuYjYjoFRZwCEQPgUgAHKaaAAAA0+ZfnAhDF0HsywAkAW1Wws2UAAAAAAAACjJ/mZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZnA=";
// root addr: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

const testBlockBoc = "te6ccgECCgEAAj8AA7d7OuqCGlYnbpJfPpxxgp6X20daSjzWT0i5iNiOgVFnAIAAAafMwCw0PszFvnhjWQYNCNMKPnfsIoCoGt7VRNC8hTNm0usAF1zwAAGnbxq1LJYug9nQADSAv8GXSAUEAQIfBQB2dGoJED4FIBiAfivOEQMCAG/JzEtATMtyiAAAAAAAAgAAAAAAA0FirgC2aIXrlD73SpqFHWjnFGcG6WU1/nIyYzTVlx40QFAZDACeQzrsBqcgAAAAAAAAAACdAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACCcpc2N4V5hGLOulaz6wVRP3oBBdc1IV2lcJrIQ+6zM43OPymQVpoUr62xy+jTQqD4wW2hiFLjQQYyeb4K3Ekx+ZUCAeAIBgEB3wcAyWn/Z11QQ0rE7dJL59OOMFPS+2jrSUeayekXMRsR0Cos4BE/zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzQ7msoAAbLc7wAADT5mAWGiMXQezojsroSAAAAAAAAAUZAAbFoAaf6IyaucIuL6xYicxjDECFpxLzJej7Z+wZAGiOzjEGZP+zrqghpWJ26SXz6ccYKel9tHWko81k9IuYjYjoFRZwCEQPgUgAHKaaAAAA0+ZfnAhDF0HsywAkAW1Wws2UAAAAAAAACjJ/mZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZnA=";
const testBocProof = "b5ee9c724102150100030f00041011ef55aa0000002a0102030428480101811859cd5ef24038d434b7da6886a68338acda1058572c7bd4225889fe881bbf000128480101ff3ed4601e8fdb725e58dc0983d33bdf11c44f692f8be94205f1c633afecbecf0003284801019d02ae73fa1264e6ea625c46f5c2c6229d1e5a01725d5709e5da1a67db9fbebc001704894a33f6fd82f5106bd98181055daf55efd3edf98a182549d62f805e75d671efcab6e071b79a9df70bbe9a40bb88b20ae47fbd626da98163638adfeac94b5912da0a16fc96c0051213140113a00fa8d1e2418ce7c0200602131007d468f120c673e010070828480101474aa93c796cf1c79ecab062ed4e081000c511f9371a30240ff1d58f242acc8d000802131004a69a0120c673e010091102110e534d01106339f0100a100259bf5e082ae888a6dd2f0a2f48455dfac5dc5b62dd7f03dba83528e99c49cb6187d4729a68088319cf808729a6810b0c28480101fad2100aa3635c13fd2c2de8bf4632eeb80b4aa7e15c2b88aacab5e7e5c1eb83000203b77b3aea821a56276e925f3e9c71829e97db475a4a3cd64f48b988d88e81516700800001a7ccc02c343eccc5be786359060d08d30a3e77ec2280a81aded544d0bc853366d2eb00175cf00001a76f1ab52c962e83d9d0003480bfc197480d0e0f2848010179aa07e8d69b49757ee0880d02773e26ba8fd8773604ba586e6d78cad63f254d000228480101035bc6ee9227c9cab7d8b351d2ab48082f5320eb6525ff4407bc4e1c1e1c6401000028480101ba524cab8af0932c180c8ca29e69e7e6ca124ed34806dbc545baa63fc7d1f130000128480101a6422018d1f5fa09d5ae92aa0f5724d41ca58c1fe353ec937f843a2d9a7a007b000528480101afd5ebf9c826e8aa98b2d7ef624817ce36afe77400058065ded109c1baa21fc10004284801018c71f032f79a0e3da0062e2ed589e75d6e34e507aab1fa792b34d253ed81f836000c28480101ee8d3086782c0cfa39b4ee650e03bae7f8ac0a37d5670622340999fdcb368702000a28480101a195a824c08c916ac464930eb7fa18bd8741fb8ad6807bd9276cd71c7d2a10a7000581a5f055";

const testTrBoc2 = "te6ccgECBwEAAYkAA69zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzAAAal4Q9ZUIVsNiQDVXJMRJrdzYPjwCv4g3Z5zbrkB3KZUbNvl/J3gAAGpeEPWVBYuz9ZwABQIBQQBAg8ECSg7rsAYEQMCAFvAAAAAAAAAAAAAAAABLUUtpEnlC4z33SeGHxRhIq/htUa7i3D8ghbwxhQTn44EAJ5Cr2wQesAAAAAAAAAAAGQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJy2+gYnnbR68HRB2RnU1Y7Z1jNX2BGTsv32z9X11pTvCejNy+RAe4Ey+dzXv29e+O3v1AJXZJosO2Op3ESH7s33gEBoAYAq2n+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE/zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzSg7rsAAAAADUvCHrKgMXZ+s5A";
const testBlockBoc2 = "b5ee9c7241020f0100025f00041011ef55aa0000002a010203042848010195a2f7db0f1d46be8824281e68af40316dca0c029cb2c40298e6c3125926592f000128480101cfc7c8576acd0f7ceaeb49ab21b85f942824956befcd8b8a19d7175cc500e1e4000328480101846a612b875cdf94dc006a3dbcc10e3d3b2aad664b26a2efa45bb1152533c299001404894a33f6fdae027cd424c99b68aa848c7676f87e5e252e17cdfe9f06739dd2c7bbc7562b8bbde9e3767d293ab3a207f408f5c30d079ae5414ccec15419d15bb5b84955fed6c0050c0d0e01038020060247a0072c9bd3f00fdc64878fc50d74a9158e2965078fa1397ee71c220aebe4558bae200610070828480101aceed5e1474b62416b87ffec5e70133c221908b7645fc2fc64b747ced3e4417f000103af7333333333333333333333333333333333333333333333333333333333333333300001a97843d654215b0d8900d55c931126b77360f8f00afe20dd9e736eb901dca6546cdbe5fc9de00001a97843d654162ecfd670001408090a0b2848010159c17c80043a67053c85261f4801f8c89c32b7687b74e49c07dfe6548ee5ff04000128480101c3f2b008c92da0afce21d07ed22ed056c51f947a7528ff44f579d831b590a38c000028480101983f21dddfbba6bd1da7996068cbc3db66758c9899184878d006c28a621b915f000128480101ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc000028480101899afde4dbbf547f37fee172db8d45b10473e6bdb087daa613b6ced63d01a4f00007284801012f3e69c8b472a2dbf515bd92467184af0b37c959bb0050ab2a3d731418af03cc00058616c86a";

const testTrBoc3 = "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";
const testBloclBoc3 = "b5ee9c72410214010002d500041011ef55aa0000002a0102030428480101e6ec57cdec46d6d17e4d70afda2adae27620494bdbf49fe9515f85a25ae47a9900012848010192db5717292ce5a7f32835b39d8d9e98dada4f213d3c368f190b59b7dddb42e5000128480101fcac764f5a69a3419e96c2211149c629aa390f764e617100f5db552f1c3c3e09002203894a33f6fd0c82fdadd94438076f5c4918389b3b124d35cb3ab595f6cfa995b006177e10dca4b60d683235d0ab66b87ea07851f6556c4adb37869366028365150dcc42bc5f40051213010ba00eb033a02006020b10075819d010070828480101d185dec0298e341bd86b0e49f73829046ddaf2ec902decdd174df3d27b419eba000f020b1004b2e3e0100911020b10048a3320100a0b2848010161e0e62a6e6efed36172f238890ebe76667c18cad05460467b811a8d56765f6400110251bf6ac7f1c1a78fe284ee515de6ebdb9c4578a238fd0b0b68231715b786421187cc627730a06627730b0c0d28480101bbb60d75964fa2dbe2ce74a63e9f6291acf5c2cb975242764959b7e734901566000303b7736443296ce4c9a6f174cc20f9644e6a7f1f5f1dd0542d58e82ee544b3252b1b200001a66c8367b03c2c095911da1dbaa6a3ffc82c5639cc04c2cbe23f74839661f18aac90e3bee3c00001a66c438245362e4560c000548069e1c1a80e0f1028480101f3e3767b1b548f61a6e309ff93ef7a275da699393356e54c754c1560a90b01dd0011284801011c4f2aa283f445d501df828fd1d7acf6877b2893d6277cee3d1fffeff760ff5b00002848010182a357dc1efdbace8d41e675d093493d4747c21c045909c091c426dd5b5ae10c0001284801015167a0042e2db53d43879c66f680c04fd18f1c815e448a1cec7899ac18473c900008284801015d59e6b2d92c8a5cced7326cda39246386e277a29d7f5ca63da8aeec607df70b00182848010194367e00a769f0fda0506524c240f732de7d1785cdbe00904fe0d52e57f3ce4e0017dd3b9adb";

const txBoc = Buffer.from(testTrBoc3, "base64");
const proofBoc = Buffer.from(testBloclBoc3, "hex");

// const bufBlock = Buffer.from(testTrBoc2, "base64");
// const bufBlock = Buffer.from(testBlockBoc2, "hex");

// const bufBlock = Buffer.from(testBlockBoc, "base64");
// const bufBlock = Buffer.from(testBocProof, "hex");

function clearData(data: any) {
  const res = Object.entries(data).reduce((acc: any, memo: any) => {
    if (['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14'].includes(memo[0])) {
      return acc;
    }
    acc[memo[0]] = memo[1];
    return acc;
  }, {} as any);
  return res;
}

describe("Greeter", function () {
  it("Should deploy Adapter", async function () {
    const Adapter = await ethers.getContractFactory("BocHeaderAdapter");
    const adapter = await Adapter.deploy();

    const [root] = await ethers.getSigners();
    await adapter.deployed();

    const res = await adapter.proofTx(txBoc, proofBoc);
    console.log(res);

    // const res = await adapter.deserialize(bufBlock);
    // const res = await adapter.deserializeMsgData(bufBlock);
    // console.log("RESULT OF DESERIALIZE: ===========");
    // const bocHeaderInfo = await adapter.parse_serialized_header(bufBlock);
    // console.log("Boc Header: ============");
    // console.log(clearData(bocHeaderInfo));

    // const cells = await adapter.get_tree_of_cells(bufBlock, bocHeaderInfo); 14 [13 [12! 11 [10 [9! 8 [7! 6]] 2!]]] !!!!!6
    // const cells: any = res;
    // console.log("CELLS: ==============");
    // console.log(cells.filter((cell: any, idx: number) => cell.bits !== "0x" && [8].includes(idx)));
    // console.log(
    //   cells.filter((cell) => cell.bits !== "0x").map((cell) => cell._hash)
    // );

    // console.log("Transaction info: ==============");
    // console.log(clearData(res));
    // console.log("In Message: ==============");
    // console.log(clearData(res.messages.inMessage));
    // console.log("Out Messages: ==============");
    // console.log(clearData(res.messages.outMessages[0]));

    // const data = await adapter.deserializeMsgData(bufBlock);
    // console.log("Data: ==============");
    // console.log(clearData(data));
    // console.log(root.address);
    // const tx = await adapter.deserializeBoc(bufBlock);
    // console.log(tx.value);
    // console.log(rTx.);
    // console.log(bufBlock);
  });

  it("tx root cell included in pruned block tree of cells and has same hash", async function() {
    const Adapter = await ethers.getContractFactory("BocHeaderAdapter");
    const adapter = await Adapter.deploy();

    const [root] = await ethers.getSigners();
    await adapter.deployed();

    const res = await adapter.proofTx(txBoc, proofBoc);
    expect(res).to.be.equal(true);
  })
});
