import { expect } from "chai";
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

const bufBlock = Buffer.from(transactionForProof2, "base64");

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

    const res = await adapter.deserialize(bufBlock);
    // const res = await adapter.deserializeMsgData(bufBlock);
    console.log("RESULT OF DESERIALIZE: ===========");
    const bocHeaderInfo = await adapter.parse_serialized_header(bufBlock);
    // console.log("Boc Header: ============");
    // console.log(clearData(bocHeaderInfo));

    const cells = await adapter.get_tree_of_cells(bufBlock, bocHeaderInfo);
    console.log("CELLS: ==============");
    // console.log(cells.filter((cell) => cell.bits !== "0x"));
    console.log(cells.filter((cell) => cell.bits !== "0x").map(cell => cell._hash));

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
});
