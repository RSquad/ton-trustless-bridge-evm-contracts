//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/TransactionTypes.sol";
import "./BitReader.sol";
import "hardhat/console.sol";

contract TransactionParser {
    function parseTransactionHeader(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 rootIdx
    ) public pure returns (TransactionHeader memory transaction) {
        transaction.checkCode = BitReader.readUint8(data, cells, rootIdx, 4);
        // addressHash
        transaction.addressHash = BitReader.readBytes32ByteSize(
            data,
            cells,
            rootIdx,
            32
        );
        // lt
        transaction.lt = BitReader.readUint64(data, cells, rootIdx, 64);
        transaction.prevTransHash = BitReader.readBytes32ByteSize(
            data,
            cells,
            rootIdx,
            32
        );
        transaction.prevTransLt = BitReader.readUint64(
            data,
            cells,
            rootIdx,
            64
        );
        transaction.time = BitReader.readUint32(data, cells, rootIdx, 32);
        transaction.OutMesagesCount = BitReader.readUint32(
            data,
            cells,
            rootIdx,
            15
        );

        transaction.oldStatus = BitReader.readUint8(data, cells, rootIdx, 2);
        transaction.newStatus = BitReader.readUint8(data, cells, rootIdx, 2);

        transaction.fees = parseCurrencyCollection(data, cells, rootIdx);
        return transaction;
    }

    function parseCurrencyCollection(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32 coins) {
        coins = readCoins(data, cells, cellIdx);
        bool check = BitReader.readBool(data, cells, cellIdx);
        if (check) {
            uint256 dcIdx = BitReader.readCell(cells, cellIdx);
            if (!cells[dcIdx].special) {
                BitReader.parseDict(data, cells, dcIdx, 32);
            }
        }

        return coins;
    }

    function readCoins(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32 value) {
        uint8 Bytes = BitReader.readUint8(data, cells, cellIdx, 4);

        if (Bytes == 0) {
            return bytes32(0);
        }
        return BitReader.readBytes32ByteSize(data, cells, cellIdx, Bytes);
    }
}
