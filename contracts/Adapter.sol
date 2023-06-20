//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./optimization/Token.sol";
import "./parser/TransactionParser.sol";
import "./parser/BitReader.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "hardhat/console.sol";

interface IBaseAdapter {
    function execute(
        bytes calldata boc,
        uint256 opcode,
        CellData[100] memory cells,
        uint256 rootIdx
    ) external;
    function swapETH(uint256 to) external payable;
    function swapToken(address from, uint256 amount, uint256 to) external;
}

contract Adapter is BitReader, Ownable, IBaseAdapter {
    MintableToken _token;
    ITransactionParser _transactionParser;
    event SwapEthereumInitialized(uint256 to, uint256 amount);
    event SwapWTONInitialized(uint256 to, uint256 amount);

    constructor(address tonToken, address transactionParser) {
        _token = MintableToken(tonToken);
        _transactionParser = ITransactionParser(transactionParser);
    }

    function execute(
        bytes calldata boc,
        uint256 opcode,
        CellData[100] memory cells,
        uint256 rootIdx
    ) public onlyOwner {
        _transactionParser.parseTransactionHeader(boc, cells, rootIdx);
        MessagesHeader memory messages = _transactionParser.parseMessagesHeader(
            boc,
            cells,
            readCell(cells, rootIdx)
        );

        TestData memory msgData = getDataFromMessages(
            boc,
            opcode,
            cells,
            messages.outMessages
        );

        if (opcode == 0x1) {
            _token.mint(msgData.amount * 1000000000, msgData.eth_address);
        }

        if (opcode == 0x2) {
            address payable receiver = payable(msgData.eth_address);
            receiver.transfer(msgData.amount);
        }
    }

    function swapETH(uint256 to) public payable {
        emit SwapEthereumInitialized(to, msg.value);
    }

    function swapToken(address from, uint256 amount, uint256 to) public {
        _token.burn(from, amount);
        emit SwapWTONInitialized(to, amount);
    }

    function getDataFromMessages(
        bytes calldata bocData,
        uint256 opcode,
        CellData[100] memory cells,
        Message[5] memory outMessages
    ) private pure returns (TestData memory data) {
        for (uint256 i = 0; i < 5; i++) {
            if (outMessages[i].info.dest.hash == bytes32(opcode)) {
                uint256 idx = outMessages[i].bodyIdx;
                // cells[outMessages[i].bodyIdx].cursor += 634;
                data.eth_address = address(
                    uint160(readUint(bocData, cells, idx, 256))
                );
                data.amount = readUint(bocData, cells, idx, 256);
            }
        }

        return data;
    }
}
