//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/BagOfCellsInfo.sol";
import "../types/CellData.sol";
import "../types/CellSerializationInfo.sol";
import "../types/TransactionTypes.sol";

interface ITreeOfCellsParser {
    function parseSerializedHeader(bytes calldata boc)
        external
        pure
        returns (BagOfCellsInfo memory header);

    function get_tree_of_cells(bytes calldata boc, BagOfCellsInfo memory info)
        external
        view
        returns (CellData[100] memory cells);
}
