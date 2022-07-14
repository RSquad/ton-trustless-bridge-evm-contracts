import { expect } from "chai";
import { ethers } from "hardhat";

const transactionBoc =
  "te6ccgECBgEAATMAA69wT2TGr7/z3RDYumcHeQrJZw1UDzepRIsDN7qmpakqysAAAZPhlKz8HrdGqXwTzwHL0QzNokz2/vEXtdYn3Gz7uPMCxnJJNKbQAAGT4ZLEtDYq8lBgABQIBQQBAgUgMDQDAgBpYAAAAJYAAAAEAAYAAAAAAAUZroTxe4+LIgJql1/1Xxqxn95KdodE0heN+mO7Uz4QekCQJrwAoEJmUBfXhAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyYT3gP0OlPbej0/Uptb3fv84uqQK9d6qfFHr4pi0ljvfDTQLN9rCtqTl05OkkT2OGuBCYi2ff56pewZCPdRJ20QABIA==";
const transactionBoc2 =
  "te6ccgECCQEAAggAA69zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzAAAVmmVRs0bhDnvty2SgMYKHnFbUgoV8Nr1YJcb3sESwZ6mm/RExsgAAFZplUbNEYg39EwADQIBQQBAg8ECQ7msoAYEQMCAGHAAAAAAAACAAAAAAACWOOfKpej3EtC+yA1UolLQuFB8LCOeI+CjSJB6Kd9tCZAUBlMAJ5CXSwGGoAAAAAAAAAAAFcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyKzPfy+2K1dlWcVuYEIqpRje+lsy2BCHs8UEmDmneNb3ugdjvxThV9GlIPPeNUCsTYmzbh4j5k95Zth3tcB0IBgIB4AgGAQHfBwDLaf5mZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZz/YBmy7sqO7h7E0J0dyfdvUBrL5r3QtiseRrYuOzWVNghDuaygAAAAAKzTKo2aOxBv6Jn////8AAAAAAAAA+iOyuhJAAMlp/sAzZd2VHdw9iaE6O5Pu3qA1l817oWxWPI1sXHZrKmwRP8zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzM0O5rKAAGy3O8AAArNMqjZojEG/omI7K6EgAAAAAAAAD6QA==";

const transaction3 = "te6cckECCQEAAjQAA7V5pN7rmQqe6px52pJdNa+SpyE0tbr8NMpvO0dtBWmJJVAAABpz1SwgO2pcsB7JSduXdX6YNLwH3tIspRC7x3SB5Ag3XHiYQImwAAAaclASwBYtAOmQADRndEUoAQIDAgHgBAUAgnLJtfkbpCwPnLxnDFheAoibKFxVT8r+hV3gR4ilSusnSUJzCR093T7s5r1s0EZmK6T2A4EQ7L27c6BLhEPUb1rlAhcEYkkO5rKAGGWL7BEHCAD5aAD4LoURgpbQwrJthc56KoxE1O8oBKjV5T5mOUvKIMtcMQAmk3uuZCp7qnHnakl01r5KnITS1uvw0ym87R20FaYklVDuaygABhRYYAAAA056pYQExaAdMgAAAAAAAAA9gIEBggKDA4QEhQWGBocHgIEBggKAAAAAAAAYHMABAd8GANfgBNJvdcyFT3VOPO1JLprXyVOQmlrdfhplN52jtoK0xJKrAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADARwzPAAABpz1SwgRi0A6ZAECAwQFBgcICQoLDA0ODwECAwQFAAAAAAAAMDmAAnkFrjD0JAAAAAAAAAAAAKgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAb8mHoSBMPQkAAAAAAAACAAAAAAADpn9fPgzYhDtiiWUBxLvx0ZlJvlQMDOuIa4wbq3hjrjBAUBrUpi0+TQ==";
  const bufBlock = Buffer.from(transaction3, "base64");

describe("Greeter", function () {
  it("Should return the new greeting once it's changed", async function () {
    const Greeter = await ethers.getContractFactory("Greeter");
    const greeter = await Greeter.deploy("Hello, world!");
    await greeter.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });

  it("Should deploy Adapter", async function () {
    const lib = await ethers.getContractFactory("UtilsLib");
    const libC = await lib.deploy();
    await libC.deployed();

    const BocHeaderReader = await ethers.getContractFactory(
      "BocHeaderInfoAdapter",
      {
        libraries: {
          UtilsLib: libC.address,
        },
      }
    );
    const bocHeaderReader = await BocHeaderReader.deploy();
    await bocHeaderReader.deployed();

    const Adapter = await ethers.getContractFactory("Adapter", {
      libraries: {
        UtilsLib: libC.address,
        BocHeaderInfoAdapter: bocHeaderReader.address,
      },
    });
    const adapter = await Adapter.deploy();
    await adapter.deployed();

    const res = await adapter.deserialize(bufBlock);
    console.log("RESULT OF DESERIALIZE: ===========");

    console.log(res.messages.outMessages[0]);
    // const tx = await adapter.deserializeBoc(bufBlock);
    // console.log(tx.value);
    // console.log(rTx.);
    // console.log(bufBlock);
  });
});
