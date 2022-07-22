//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./BocHeaderInfoAdapter.sol";
import "./TreeOfCellsAdapter.sol";
import "./UtilsLib.sol";

    struct TonAddress {
        bytes32 hash;
        uint8 wc;
    }

    struct RawCommonMessageInfo {
        uint Type;
        bool ihrDisabled;
        bool bounce;
        bool bounced;
        TonAddress src;
        TonAddress dest;
        // value RawCurrencyCollection
        bytes32 value;
        bytes32 ihrFee;
        bytes32 fwdFee;
        uint createdLt;
        uint createdAt;
        bytes32 importFee;
    }

    struct Message {
        RawCommonMessageInfo info;
        uint bodyIdx;
    }

    struct MessagesHeader {
        bool hasInMessage;
        bool hasOutMessages;

        Message inMessage;
        Message[5] outMessages;
    }

    struct TransactionHeader {
        uint8 checkCode;
        bytes32 addressHash;
        uint64 lt;
        bytes32 prevTransHash;
        uint64 prevTransLt;

        uint32 time;
        uint32 OutMesagesCount;

        uint8 oldStatus;
        uint8 newStatus;

        bytes32 fees;

        MessagesHeader messages;
    }

    struct TestData {
        address eth_address;
        uint amount;
    }

contract BocHeaderAdapter is TreeOfCellsAdapter {
    function parseTransactionHeader(CellData[50] memory cells, uint rootIdx) public pure returns (TransactionHeader memory transaction) {
        transaction.checkCode = readUint8(cells, rootIdx, 4);

        // addressHash
        transaction.addressHash = readBytes32(cells, rootIdx, 32);
        // lt
        transaction.lt = readUint64(cells, rootIdx, 64);
        transaction.prevTransHash = readBytes32(cells, rootIdx, 32);
        transaction.prevTransLt = readUint64(cells, rootIdx, 64);
        transaction.time = readUint32(cells, rootIdx, 32);
        transaction.OutMesagesCount = readUint32(cells, rootIdx, 15);

        transaction.oldStatus = readUint8(cells, rootIdx, 2);
        transaction.newStatus = readUint8(cells, rootIdx, 2);

        transaction.fees = parseCurrencyCollection(cells, rootIdx);
        return transaction;
    }

    function parseCurrencyCollection(CellData[50] memory cells, uint cellIdx) public pure returns (bytes32 coins) {
        coins = readCoins(cells, cellIdx);
        bool check = readBool(cells, cellIdx);
        if (check) {
            uint dcIdx = readCell(cells, cellIdx);
            if (!cells[dcIdx].special) {
                parseDict(cells, dcIdx, 32);
            }
        }

        return coins;
    }

    function parseDict(CellData[50] memory cells, uint cellIdx, uint keySize) public pure returns (uint[5] memory cellIdxs) {
        for (uint i = 0; i < 5; i++) {
            cellIdxs[i] = 255;
        }
        doParse(0, cells, cellIdx, keySize, cellIdxs);
        return cellIdxs;
    }

    function doParse(uint prefix, CellData[50] memory cells, uint cellIdx, uint n, uint[5] memory cellIdxs) public pure {
        uint prefixLength = 0;
        uint pp = prefix;

        // lb0
        if (!readBool(cells, cellIdx)) {
            // Short label detected
            // console.log("Short label detected");
            prefixLength = readUnaryLength(cells, cellIdx);

            for (uint i = 0; i < prefixLength; i++) {
                pp = pp << 1 + readBit(cells, cellIdx);
            }
        } else {
            // lb1
            if (!readBool(cells, cellIdx)) {
                // long label detected
                // console.log("Long label detected");
                prefixLength = readUint64(cells, cellIdx, uint8(log2Ceil(n)));
                for (uint i = 0; i < prefixLength; i++) {
                    pp = pp << 1 + readBit(cells, cellIdx);
                }
            } else {
                // Same label detected
                // console.log("Same label detected");
                uint bit = readBit(cells, cellIdx);
                prefixLength = readUint64(cells, cellIdx, uint8(log2Ceil(n)));
                for (uint i = 0; i < prefixLength; i++) {
                    pp = pp << 1 + bit;
                }
            }
        }
        if (n - prefixLength == 0) {
            // end
            cellIdxs[pp] = cellIdx;
            // res.set(new BN(pp, 2).toString(10), extractor(slice));
        } else {
            uint leftIdx = readCell(cells, cellIdx);
            uint rightIdx = readCell(cells, cellIdx);
            // NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (leftIdx != 255 && !cells[leftIdx].special) {
                doParse(pp << 1, cells, leftIdx, n - prefixLength - 1, cellIdxs);
            }
            if (rightIdx != 255 && !cells[rightIdx].special) {
                doParse(pp << 1 + 1, cells, rightIdx, n - prefixLength - 1, cellIdxs);
            }
        }
    }

    function readCoins(CellData[50] memory cells, uint cellIdx) public pure returns (bytes32 value) {
        uint8 Bytes = readUint8(cells, cellIdx, 4);

        if (Bytes == 0) {
            return bytes32(0);
        }
        return readBytes32(cells, cellIdx, Bytes);
    }

    function parseMessagesHeader(CellData[50] memory cells, uint messagesIdx) public pure returns (MessagesHeader memory messagesHeader) {
        messagesHeader.hasInMessage = readBool(cells, messagesIdx);
        messagesHeader.hasOutMessages = readBool(cells, messagesIdx);
        if (messagesHeader.hasInMessage) {
            messagesHeader.inMessage = parseMessage(cells, readCell(cells, messagesIdx));
        }

        if (messagesHeader.hasOutMessages) {
            uint[5] memory cellIdxs = parseDict(cells, readCell(cells, messagesIdx), 15);
            uint j = 0;
            for (uint i = 0; i < 5; i++) {
                if (cellIdxs[i] != 255) {
                    messagesHeader.outMessages[j] = parseMessage(cells, readCell(cells, cellIdxs[i]));
                    j++;
                }
            }
        }

        return messagesHeader;
    }

    function getDataFromMessages(CellData[50] memory cells, Message[5] memory outMessages) public pure returns (TestData memory data) {
        for (uint i = 0; i < 5; i++) {
            if (outMessages[i].info.dest.hash == bytes32(uint(0xc0470ccf))) {
                uint idx = outMessages[i].bodyIdx;
                data.eth_address = address(uint160(readUint(cells, idx, 160)));
                data.amount = readUint64(cells, idx, 64);
            }
        }

        return data;
    }

    function parseMessage(CellData[50] memory cells, uint messagesIdx) public pure returns (Message memory message) {
        message.info = parseCommonMsgInfo(cells, messagesIdx);
        bool hasInit = readBool(cells, messagesIdx);
        if (hasInit) {
            if (readBool(cells, messagesIdx)) {
                // init = parseStateInit(slice);
            } else {
                // init = parseStateInit(slice.readRef());
                readCell(cells, messagesIdx);
            }
        }

        message.bodyIdx = readBool(cells, messagesIdx) ? readCell(cells, messagesIdx) : messagesIdx;

        return message;
    }


    function parseCommonMsgInfo(CellData[50] memory cells, uint messagesIdx) public pure returns (RawCommonMessageInfo memory msgInfo) {
        if (!readBool(cells, messagesIdx)) {
            // internal
            // console.log("internal");
            msgInfo.ihrDisabled = readBool(cells, messagesIdx);
            msgInfo.bounce = readBool(cells, messagesIdx);
            msgInfo.bounced = readBool(cells, messagesIdx);

            msgInfo.src = readAddress(cells, messagesIdx);
            msgInfo.dest = readAddress(cells, messagesIdx);

            msgInfo.value = parseCurrencyCollection(cells, messagesIdx);
            msgInfo.ihrFee = readCoins(cells, messagesIdx);
            msgInfo.fwdFee = readCoins(cells, messagesIdx);
            msgInfo.createdLt = readUint64(cells, messagesIdx, 64);
            msgInfo.createdAt = readUint32(cells, messagesIdx, 32);
        } else if (readBool(cells, messagesIdx)) {
            // Outgoing external
            // console.log("Outgoing external");
            msgInfo.src = readAddress(cells, messagesIdx);
            msgInfo.dest = readAddress(cells, messagesIdx);

            msgInfo.createdLt = readUint64(cells, messagesIdx, 64);
            msgInfo.createdAt = readUint32(cells, messagesIdx, 32);
        } else {
            // Incoming external
            // console.log("Incoming external");
            msgInfo.src = readAddress(cells, messagesIdx);
            msgInfo.dest = readAddress(cells, messagesIdx);
            msgInfo.importFee = readCoins(cells, messagesIdx);
        }

        return msgInfo;
    }

    function readAddress(CellData[50] memory cells, uint messagesIdx) public pure returns (TonAddress memory addr) {
        uint8 Type = readUint8(cells, messagesIdx, 2);

        if (Type == 0) {
            return addr;
        }
        if (Type == 1) {
            uint16 len = uint16(readUint64(cells, messagesIdx, 9));
            addr.hash = readBytes32_2(cells, messagesIdx, len);
            return addr;
        }

        require(Type == 2, "Only STD address supported TYPE ERROR");
        uint8 bit = readBit(cells, messagesIdx);

        require(bit == 0, "Only STD address supported BIT ERROR");

        addr.wc = readUint8(cells, messagesIdx, 8);

        addr.hash = readBytes32(cells, messagesIdx, 32);

        return addr;
    }

    function deserialize(bytes calldata boc) public pure returns (TransactionHeader memory transaction) {
        BagOfCellsInfo memory info = BocHeaderInfoAdapter.parse_serialized_header(boc);

        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[50] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint rootIdx = info.cell_count - UtilsLib.read_int(boc[info.roots_offset :], info.ref_byte_size) - 1;

        CellData[50] memory cells = get_tree_of_cells(boc, info);

        // for (uint i = 0; i < 50; i++) {
        //     console.logBytes(cells[i].bits);
        //     console.log("==============");
        // }

        transaction = parseTransactionHeader(cells, rootIdx);
        transaction.messages = parseMessagesHeader(cells, readCell(cells, rootIdx));

        return transaction;
    }

    function deserializeMsgData(bytes calldata boc) public pure returns (TestData memory data) {
        BagOfCellsInfo memory info = BocHeaderInfoAdapter.parse_serialized_header(boc);

        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[50] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint rootIdx = info.cell_count - UtilsLib.read_int(boc[info.roots_offset :], info.ref_byte_size) - 1;

        CellData[50] memory cells = get_tree_of_cells(boc, info);

        parseTransactionHeader(cells, rootIdx);
        MessagesHeader memory messages = parseMessagesHeader(cells, readCell(cells, rootIdx));


        return getDataFromMessages(cells, messages.outMessages);
    }

    function readBit(CellData[50] memory cells, uint cellIdx) public pure returns (uint8 value) {
        uint cursor = cells[cellIdx].cursor / 8;
        uint bytesStart = cells[cellIdx].cursor % 8;
        value = uint8(cells[cellIdx].bits[cursor] << bytesStart >> 7);
        cells[cellIdx].cursor += 1;
        return value;
    }

    function readBool(CellData[50] memory cells, uint cellIdx) public pure returns (bool value) {
        return readBit(cells, cellIdx) == 1;
    }

    function readUint8(CellData[50] memory cells, uint cellIdx, uint8 size) public pure returns (uint8 value) {
        require(size <= 8, "max size is 8 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint32(CellData[50] memory cells, uint cellIdx, uint8 size) public pure returns (uint32 value) {
        require(size <= 32, "max size is 32 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint64(CellData[50] memory cells, uint cellIdx, uint16 size) public pure returns (uint64 value) {
        require(size <= 64, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint(CellData[50] memory cells, uint cellIdx, uint16 size) public pure returns (uint value) {
        require(size <= 256, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readBytes32_2(CellData[50] memory cells, uint cellIdx, uint size) public pure returns (bytes32 buffer) {
        uint value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readBytes32(CellData[50] memory cells, uint cellIdx, uint sizeb) public pure returns (bytes32 buffer) {
        uint size = sizeb * 8;
        uint value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readCell(CellData[50] memory cells, uint cellIdx) public pure returns (uint idx) {
        idx = cells[cellIdx].refs[cells[cellIdx].cursorRef];
        cells[cellIdx].cursorRef++;
        return idx;
    }

    function readUnaryLength(CellData[50] memory cells, uint cellIdx) public pure returns (uint value) {
        value = 0;
        while (readBool(cells, cellIdx)) {
            value++;
        }
        return value;
    }


    function log2Ceil(uint x) public pure returns (uint n) {
        bool check = false;

        for (n = 0; x > 1; x >>= 1) {
            n += 1;

            if (x & 1 == 1 && !check) {
                n += 1;
                check = true;
            }
        }

        if (x == 1 && !check) {
            n += 1;
        }

        return n;
    }
}