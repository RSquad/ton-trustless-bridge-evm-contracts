//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./optimization/Token.sol";
import "./parser/TransactionParser.sol";
import "./parser/BitReader.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBaseAdapter {
    function execute(
        bytes calldata boc,
        CellData[100] memory cells,
        uint256 rootIdx
        ) external;
}

contract Adapter is BitReader, Ownable, IBaseAdapter {
    MintableToken _token;
    ITransactionParser _transactionParser;

    constructor(address tonToken, address transactionParser) {
        _token = MintableToken(tonToken);
        _transactionParser = ITransactionParser(transactionParser);
    }

    function execute(
        bytes calldata boc,
        CellData[100] memory cells,
        uint256 rootIdx
        ) public onlyOwner {
        _transactionParser.parseTransactionHeader(boc, cells, rootIdx);
        MessagesHeader memory messages = _transactionParser.parseMessagesHeader(
            boc,
            cells,
            readCell(cells, rootIdx)
        );

        // TestData memory msgData = getDataFromMessages(boc, cells, messages.outMessages);
        // _token.mint(msgData.amount, msgData.eth_address);
    }

    function getDataFromMessages(
        bytes calldata bocData,
        CellData[100] memory cells,
        Message[5] memory outMessages
    ) private pure returns (TestData memory data) {
        for (uint256 i = 0; i < 5; i++) {
            if (outMessages[i].info.dest.hash == bytes32(uint256(0xc0470ccf))) {
                uint256 idx = outMessages[i].bodyIdx;
                data.eth_address = address(
                    uint160(readUint(bocData, cells, idx, 160))
                );
                data.amount = readUint64(bocData, cells, idx, 64);
            }
        }

        return data;
    }
}
