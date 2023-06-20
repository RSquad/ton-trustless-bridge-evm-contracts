//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "./parser/BlockParser.sol";
import "./parser/TransactionParser.sol";
import "./parser/TreeOfCellsParser.sol";
import "./Validator.sol";
import "./Adapter.sol";

contract Bridge {
    IBlockParser _blockParser;
    ITransactionParser _transactionParser;
    ITreeOfCellsParser _treeOfCellsParser;
    IValidator _validator;

    constructor(
        address blockParser,
        address transactionParser,
        address treeOfCellsParser,
        address validatorAddr
    ) {
        _blockParser = IBlockParser(blockParser);
        _transactionParser = ITransactionParser(transactionParser);
        _treeOfCellsParser = ITreeOfCellsParser(treeOfCellsParser);
        _validator = IValidator(validatorAddr);
    }

    receive() external payable {} // to support receiving ETH by default

    fallback() external payable {}

    function readTransaction(
        bytes calldata txBoc,
        bytes calldata blockBoc,
        address adapterAddr,
        uint256 opcode
    ) public {
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

        require(
            _validator.isVerifiedBlock(blockToc[blockHeader.rootIdx]._hash[0]),
            "invalid block"
        );

        TransactionHeader memory txInfo = _transactionParser
            .parseTransactionHeader(txBoc, txToC, txHeader.rootIdx);
        bool isValid = _blockParser.parse_block(
            blockBoc,
            blockHeader,
            blockToc,
            txToC[txHeader.rootIdx]._hash[0],
            txInfo
        );

        require(isValid, "Wrong block for transaction");

        IBaseAdapter adapter = IBaseAdapter(adapterAddr);
        adapter.execute(txBoc, opcode, txToC, txHeader.rootIdx);
    }

    function swapETH(uint256 to, address adapterAddr) public payable {
        IBaseAdapter adapter = IBaseAdapter(adapterAddr);
        adapter.swapETH{value: msg.value}(to);
    }

    function swapToken(
        address from,
        uint256 amount,
        uint256 to,
        address adapterAddr
    ) public {
        IBaseAdapter adapter = IBaseAdapter(adapterAddr);
        adapter.swapToken(from, amount, to);
    }
}
