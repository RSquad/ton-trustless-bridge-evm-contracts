//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./IBlockParser.sol";
import "./ITransactionParser.sol";
import "./ITreeOfCellsParser.sol";
import "./Token.sol";

contract Bridge {
    IBlockParser _blockParser;
    ITransactionParser _transactionParser;
    ITreeOfCellsParser _treeOfCellsParser;
    MintableToken _token;

    constructor(
        address blockParser,
        address transactionParser,
        address treeOfCellsParser,
        address tonToken
    ) {
        _blockParser = IBlockParser(blockParser);
        _transactionParser = ITransactionParser(transactionParser);
        _treeOfCellsParser = ITreeOfCellsParser(treeOfCellsParser);
        _token = MintableToken(tonToken);
    }

    function readTransaction(bytes calldata txBoc, bytes calldata blockBoc)
        public 
    {
        BagOfCellsInfo memory txHeader = _treeOfCellsParser
            .parseSerializedHeader(txBoc);
        BagOfCellsInfo memory blockHeader = _treeOfCellsParser
            .parseSerializedHeader(blockBoc);

        CellData[100] memory txToC = _treeOfCellsParser.get_tree_of_cells(
            txBoc,
            txHeader
        );
        CellData[100] memory blockToc = _treeOfCellsParser.get_tree_of_cells(
            blockBoc,
            blockHeader
        );

        TransactionHeader memory txInfo = _transactionParser.parseTransactionHeader(txBoc, txToC, txHeader.rootIdx);
        bool isValid = _blockParser.parse_block(blockBoc, blockHeader, blockToc, txToC[txHeader.rootIdx]._hash[0], txInfo);

        require(isValid, "Wrong block for transaction");

        TestData memory msgData = _transactionParser.deserializeMsgDate(txBoc, txToC, txHeader.rootIdx);

        _token.mint(msgData.amount, msgData.eth_address);
    }
}
