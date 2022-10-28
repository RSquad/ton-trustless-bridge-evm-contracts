//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BagOfCellsInfo.sol";
import "./BitReader.sol";
import "../types/TransactionTypes.sol";

interface IBlockParser {
    function parse_block(
        bytes calldata proofBoc,
        BagOfCellsInfo memory proofBocInfo,
        CellData[100] memory proofTreeOfCells,
        bytes32 txRootHash,
        TransactionHeader memory transaction
    ) external view returns (bool);
}
