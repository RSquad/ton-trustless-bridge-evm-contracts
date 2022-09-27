//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "../types/TransactionTypes.sol";
import "./BitReader.sol";
import "hardhat/console.sol";

contract TransactionParser is BitReader {
    function parseTransactionHeader(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 rootIdx
    ) public pure returns (TransactionHeader memory transaction) {
        transaction.checkCode = readUint8(data, cells, rootIdx, 4);
        // addressHash
        transaction.addressHash = readBytes32ByteSize(
            data,
            cells,
            rootIdx,
            32
        );
        // lt
        transaction.lt = readUint64(data, cells, rootIdx, 64);
        transaction.prevTransHash = readBytes32ByteSize(
            data,
            cells,
            rootIdx,
            32
        );
        transaction.prevTransLt = readUint64(
            data,
            cells,
            rootIdx,
            64
        );
        transaction.time = readUint32(data, cells, rootIdx, 32);
        transaction.OutMesagesCount = readUint32(
            data,
            cells,
            rootIdx,
            15
        );

        transaction.oldStatus = readUint8(data, cells, rootIdx, 2);
        transaction.newStatus = readUint8(data, cells, rootIdx, 2);

        transaction.fees = parseCurrencyCollection(data, cells, rootIdx);
        return transaction;
    }

    function parseCurrencyCollection(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32 coins) {
        coins = readCoins(data, cells, cellIdx);
        bool check = readBool(data, cells, cellIdx);
        if (check) {
            uint256 dcIdx = readCell(cells, cellIdx);
            if (!cells[dcIdx].special) {
                parseDict(data, cells, dcIdx, 32);
            }
        }

        return coins;
    }

    function readCoins(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public pure returns (bytes32 value) {
        uint8 Bytes = readUint8(data, cells, cellIdx, 4);

        if (Bytes == 0) {
            return bytes32(0);
        }
        return readBytes32ByteSize(data, cells, cellIdx, Bytes);
    }

    function parseMessagesHeader(
        bytes calldata data,
        CellData[100] memory cells,
        uint256 messagesIdx
    ) public view returns (MessagesHeader memory messagesHeader) {
        messagesHeader.hasInMessage = readBool(data, cells, messagesIdx);
        messagesHeader.hasOutMessages = readBool(data, cells, messagesIdx);
        if (messagesHeader.hasInMessage) {
            messagesHeader.inMessage = parseMessage(
                data, 
                cells,
                readCell(cells, messagesIdx)
            );
        }

        if (messagesHeader.hasOutMessages) {
            uint256[30] memory cellIdxs = parseDict(
                data,
                cells,
                readCell(cells, messagesIdx),
                15
            );
            uint256 j = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (cellIdxs[i] != 255) {
                    messagesHeader.outMessages[j] = parseMessage(
                        data, 
                        cells,
                        readCell(cells, cellIdxs[i])
                    );
                    j++;
                }
            }
        }

        return messagesHeader;
    }

    function getDataFromMessages(
        bytes calldata bocData,
        CellData[100] memory cells,
        Message[5] memory outMessages
    ) public pure returns (TestData memory data) {
        for (uint256 i = 0; i < 5; i++) {
            if (outMessages[i].info.dest.hash == bytes32(uint256(0xc0470ccf))) {
                uint256 idx = outMessages[i].bodyIdx;
                data.eth_address = address(uint160(readUint(bocData, cells, idx, 160)));
                data.amount = readUint64(bocData, cells, idx, 64);
            }
        }

        return data;
    }

    function parseMessage(
        bytes calldata data,
        CellData[100] memory cells, uint256 messagesIdx)
        public
        view
        returns (Message memory message)
    {
        message.info = parseCommonMsgInfo(data, cells, messagesIdx);
        bool hasInit = readBool(data, cells, messagesIdx);
        if (hasInit) {
            if (readBool(data, cells, messagesIdx)) {
                // init = parseStateInit(slice);
            } else {
                // init = parseStateInit(slice.readRef());
                readCell(cells, messagesIdx);
            }
        }

        message.bodyIdx = readBool(data, cells, messagesIdx)
            ? readCell(cells, messagesIdx)
            : messagesIdx;

        return message;
    }

    function parseCommonMsgInfo(
        bytes calldata data,
        CellData[100] memory cells, uint256 messagesIdx)
        public
        view
        returns (RawCommonMessageInfo memory msgInfo)
    {
        if (!readBool(data, cells, messagesIdx)) {
            // internal
            // console.log("internal");
            msgInfo.ihrDisabled = readBool(data, cells, messagesIdx);
            msgInfo.bounce = readBool(data, cells, messagesIdx);
            msgInfo.bounced = readBool(data, cells, messagesIdx);

            msgInfo.src = readAddress(data, cells, messagesIdx);
            msgInfo.dest = readAddress(data, cells, messagesIdx);

            msgInfo.value = parseCurrencyCollection(data, cells, messagesIdx);
            msgInfo.ihrFee = readCoins(data, cells, messagesIdx);
            msgInfo.fwdFee = readCoins(data, cells, messagesIdx);
            msgInfo.createdLt = readUint64(data, cells, messagesIdx, 64);
            msgInfo.createdAt = readUint32(data, cells, messagesIdx, 32);
        } else if (readBool(data, cells, messagesIdx)) {
            // Outgoing external
            // console.log("Outgoing external");
            msgInfo.src = readAddress(data, cells, messagesIdx);
            msgInfo.dest = readAddress(data, cells, messagesIdx);

            msgInfo.createdLt = readUint64(data, cells, messagesIdx, 64);
            msgInfo.createdAt = readUint32(data, cells, messagesIdx, 32);
        } else {
            // Incoming external
            // console.log("Incoming external");
            msgInfo.src = readAddress(data, cells, messagesIdx);
            msgInfo.dest = readAddress(data, cells, messagesIdx);
            msgInfo.importFee = readCoins(data, cells, messagesIdx);
        }

        return msgInfo;
    }

    function readAddress(bytes calldata data,CellData[100] memory cells, uint256 messagesIdx)
        public
        pure
        returns (TonAddress memory addr)
    {
        uint8 Type = readUint8(data, cells, messagesIdx, 2);

        if (Type == 0) {
            return addr;
        }
        if (Type == 1) {
            uint16 len = uint16(readUint64(data, cells, messagesIdx, 9));
            addr.hash = readBytes32BitSize(data, cells, messagesIdx, len);
            return addr;
        }

        require(Type == 2, "Only STD address supported TYPE ERROR");
        uint8 bit = readBit(data, cells, messagesIdx);

        require(bit == 0, "Only STD address supported BIT ERROR");

        addr.wc = readUint8(data, cells, messagesIdx, 8);

        addr.hash = readBytes32ByteSize(data, cells, messagesIdx, 32);

        return addr;
    }

}
