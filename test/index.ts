import { expect } from "chai";
import { ethers } from "hardhat";

const transactionBoc = "te6ccgECBgEAATMAA69wT2TGr7/z3RDYumcHeQrJZw1UDzepRIsDN7qmpakqysAAAZPhlKz8HrdGqXwTzwHL0QzNokz2/vEXtdYn3Gz7uPMCxnJJNKbQAAGT4ZLEtDYq8lBgABQIBQQBAgUgMDQDAgBpYAAAAJYAAAAEAAYAAAAAAAUZroTxe4+LIgJql1/1Xxqxn95KdodE0heN+mO7Uz4QekCQJrwAoEJmUBfXhAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIJyYT3gP0OlPbej0/Uptb3fv84uqQK9d6qfFHr4pi0ljvfDTQLN9rCtqTl05OkkT2OGuBCYi2ff56pewZCPdRJ20QABIA==";
const bufBlock = Buffer.from(transactionBoc, 'base64');

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
    const Adapter = await ethers.getContractFactory("Adapter");
    const adapter = await Adapter.deploy();
    await adapter.deployed();

    const res = await adapter.deserialize(bufBlock);
    console.log(res);
    // const tx = await adapter.deserializeBoc(bufBlock);
    // console.log(tx.value);
    // console.log(rTx.);
    // console.log(bufBlock);
  });
});
