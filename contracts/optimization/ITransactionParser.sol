//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/TransactionTypes.sol";
import "./BitReader.sol";

interface ITransactionParser {
    function deserializeMsgDate(
        bytes calldata boc,
        CellData[100] memory cells,
        uint256 rootIdx
    ) external view returns (TestData memory data);

    function parseTransactionHeader(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 rootIdx
    ) external view returns (TransactionHeader memory transaction);
}
