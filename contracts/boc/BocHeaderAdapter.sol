//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";

struct BagOfCellsInfo {
    bytes4 magic;
    uint256 root_count;
    uint256 cell_count;
    uint256 absent_count;
    uint256 ref_byte_size;
    uint256 offset_byte_size;
    bool has_index;
    bool has_roots;
    bool has_crc32c;
    bool has_cache_bits;
    uint256 roots_offset;
    uint256 index_offset;
    uint256 data_offset;
    uint256 data_size;
    uint256 total_size;
}

struct CellData {
    bool special;
    uint8 cellType;
    bytes bits;
    uint256[4] refs;
    uint256 cursor;
    uint8 cursorRef;
    bytes32[4] _hash;
    uint32 level_mask;
    uint16[4] depth;
}

struct CellSerializationInfo {
    bool special;
    uint32 level_mask;
    bool with_hashes;
    uint256 hashes_offset;
    uint256 depth_offset;
    uint256 data_offset;
    uint256 data_len;
    bool data_with_bits;
    uint256 refs_offset;
    uint256 refs_cnt;
    uint256 end_offset;
}

struct TonAddress {
    bytes32 hash;
    uint8 wc;
}

struct RawCommonMessageInfo {
    uint256 Type;
    bool ihrDisabled;
    bool bounce;
    bool bounced;
    TonAddress src;
    TonAddress dest;
    // value RawCurrencyCollection
    bytes32 value;
    bytes32 ihrFee;
    bytes32 fwdFee;
    uint256 createdLt;
    uint256 createdAt;
    bytes32 importFee;
}

struct Message {
    RawCommonMessageInfo info;
    uint256 bodyIdx;
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
    uint256 amount;
}

contract BocHeaderAdapter {
    bytes4 public constant boc_idx = 0x68ff65f3;
    bytes4 public constant boc_idx_crc32c = 0xacc3a728;
    bytes4 public constant boc_generic = 0xb5ee9c72;

    uint8 public constant OrdinaryCell = 255;
    uint8 public constant PrunnedBranchCell = 1;
    uint8 public constant LibraryCell = 2;
    uint8 public constant MerkleProofCell = 3;
    uint8 public constant MerkleUpdateCell = 4;

    function parse_serialized_header(bytes calldata boc)
        public
        view
        returns (BagOfCellsInfo memory header)
    {
        uint256 sz = boc.length;
        require(!(sz < 4), "Not enough bytes");

        uint256 ptr = 0;
        header = BagOfCellsInfo(
            bytes4(boc[0:4]), // magic
            0, // root_count
            0, // cell_count
            0, // absent_count
            0, // ref_byte_size
            0, // offset_byte_size
            false, // has_index
            false, // has_roots
            false, // has_crc32c
            false, // has_cache_bits
            0, // roots_offset
            0, // index_offset
            0, // data_offset
            0, // data_size
            0 // total_size
        );
        // console.log("Header magic");
        // console.logBytes(boc);
        // console.logBytes4(header.magic);
        require(
            !(header.magic != boc_generic &&
                header.magic != boc_idx &&
                header.magic != boc_idx_crc32c),
            "wrong boc type"
        );

        uint8 flags_byte = uint8(boc[4]);

        if (header.magic == boc_generic) {
            header.has_index = (flags_byte >> 7) % 2 == 1;
            header.has_crc32c = (flags_byte >> 6) % 2 == 1;
            header.has_cache_bits = (flags_byte >> 5) % 2 == 1;
        } else {
            header.has_index = true;
            header.has_crc32c = header.magic == boc_idx_crc32c;
        }

        require(
            !(header.has_cache_bits && !header.has_index),
            "bag-of-cells: invalid header"
        );

        header.ref_byte_size = flags_byte & 7;
        require(
            !(header.ref_byte_size > 4 || header.ref_byte_size < 1),
            "bag-of-cells: invalid header"
        );
        require(!(sz < 6), "bag-of-cells: invalid header");

        header.offset_byte_size = uint8(boc[5]);
        require(
            !(header.offset_byte_size > 8 || header.offset_byte_size < 1),
            "bag-of-cells: invalid header"
        );
        header.roots_offset =
            6 +
            3 *
            header.ref_byte_size +
            header.offset_byte_size;
        ptr += 6;
        sz -= 6;
        require(!(sz < header.ref_byte_size), "bag-of-cells: invalid header");

        header.cell_count = read_int(boc[ptr:], header.ref_byte_size);
        require(!(header.cell_count <= 0), "bag-of-cells: invalid header");
        require(
            !(sz < 2 * header.ref_byte_size),
            "bag-of-cells: invalid header"
        );
        header.root_count = read_int(
            boc[ptr + header.ref_byte_size:],
            header.ref_byte_size
        );
        require(!(header.root_count <= 0), "bag-of-cells: invalid header");
        header.index_offset = header.roots_offset;
        if (header.magic == boc_generic) {
            header.index_offset += header.root_count * header.ref_byte_size;
            header.has_roots = true;
        } else {
            require(!(header.root_count != 1), "bag-of-cells: invalid header");
        }
        header.data_offset = header.index_offset;
        if (header.has_index) {
            header.data_offset += header.cell_count * header.offset_byte_size;
        }
        require(
            !(sz < 3 * header.ref_byte_size),
            "bag-of-cells: invalid header"
        );
        header.absent_count = read_int(
            boc[ptr + 2 * header.ref_byte_size:],
            header.ref_byte_size
        );
        require(
            !(header.absent_count < 0 ||
                header.absent_count > header.cell_count),
            "bag-of-cells: invalid header"
        );
        require(
            !(sz < 3 * header.ref_byte_size + header.offset_byte_size),
            "bag-of-cells: invalid header"
        );
        header.data_size = read_int(
            boc[ptr + 3 * header.ref_byte_size:],
            header.offset_byte_size
        );
        require(
            !(header.data_size > header.cell_count << 10),
            "bag-of-cells: invalid header"
        );

        header.total_size =
            header.data_offset +
            header.data_size +
            (header.has_crc32c ? 4 : 0);
        return header;
    }

    function parseTransactionHeader(CellData[100] memory cells, uint256 rootIdx)
        public
        view
        returns (TransactionHeader memory transaction)
    {
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

    function parseCurrencyCollection(
        CellData[100] memory cells,
        uint256 cellIdx
    ) public view returns (bytes32 coins) {
        coins = readCoins(cells, cellIdx);
        bool check = readBool(cells, cellIdx);
        if (check) {
            uint256 dcIdx = readCell(cells, cellIdx);
            if (!cells[dcIdx].special) {
                parseDict(cells, dcIdx, 32);
            }
        }

        return coins;
    }

    function parseDict(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 keySize
    ) public view returns (uint256[10] memory cellIdxs) {
        for (uint256 i = 0; i < 10; i++) {
            cellIdxs[i] = 255;
        }
        doParse(0, cells, cellIdx, keySize, cellIdxs);
        return cellIdxs;
    }

    function doParse(
        uint256 prefix,
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 n,
        uint256[10] memory cellIdxs
    ) public view {
        uint256 prefixLength = 0;
        uint256 pp = prefix;

        // lb0
        if (!readBool(cells, cellIdx)) {
            // Short label detected
            prefixLength = readUnaryLength(cells, cellIdx);
            console.log("Short label detected", cellIdx, n, prefixLength);

            for (uint256 i = 0; i < prefixLength; i++) {
                pp = (pp << 1) + readBit(cells, cellIdx);
            }
        } else {
            // lb1
            if (!readBool(cells, cellIdx)) {
                // long label detected
                prefixLength = readUint64(cells, cellIdx, uint8(log2Ceil(n)));
                console.log("Long label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + readBit(cells, cellIdx);
                }
            } else {
                // Same label detected
                uint256 bit = readBit(cells, cellIdx);
                prefixLength = readUint64(cells, cellIdx, uint8(log2Ceil(n)));
                console.log("Same label detected", cellIdx, n, prefixLength);
                for (uint256 i = 0; i < prefixLength; i++) {
                    pp = (pp << 1) + bit;
                }
            }
        }
        if (n - prefixLength == 0) {
            // end
            for (uint256 i = 0; i < 10; i++) {
                if (cellIdxs[i] == 255) {
                    cellIdxs[i] = cellIdx;
                    break;
                }
            }
            // cellIdxs[pp] = cellIdx;
            // res.set(new BN(pp, 2).toString(10), extractor(slice));
        } else {
            uint256 leftIdx = readCell(cells, cellIdx);
            uint256 rightIdx = readCell(cells, cellIdx);
            // NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (leftIdx != 255 && !cells[leftIdx].special) {
                doParse(
                    pp << 1,
                    cells,
                    leftIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            }
            if (rightIdx != 255 && !cells[rightIdx].special) {
                doParse(
                    pp << (1 + 1),
                    cells,
                    rightIdx,
                    n - prefixLength - 1,
                    cellIdxs
                );
            }
        }
    }

    function readCoins(CellData[100] memory cells, uint256 cellIdx)
        public
        pure
        returns (bytes32 value)
    {
        uint8 Bytes = readUint8(cells, cellIdx, 4);

        if (Bytes == 0) {
            return bytes32(0);
        }
        return readBytes32(cells, cellIdx, Bytes);
    }

    function parseMessagesHeader(
        CellData[100] memory cells,
        uint256 messagesIdx
    ) public view returns (MessagesHeader memory messagesHeader) {
        messagesHeader.hasInMessage = readBool(cells, messagesIdx);
        messagesHeader.hasOutMessages = readBool(cells, messagesIdx);
        if (messagesHeader.hasInMessage) {
            messagesHeader.inMessage = parseMessage(
                cells,
                readCell(cells, messagesIdx)
            );
        }

        if (messagesHeader.hasOutMessages) {
            uint256[10] memory cellIdxs = parseDict(
                cells,
                readCell(cells, messagesIdx),
                15
            );
            uint256 j = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (cellIdxs[i] != 255) {
                    messagesHeader.outMessages[j] = parseMessage(
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
        CellData[100] memory cells,
        Message[5] memory outMessages
    ) public pure returns (TestData memory data) {
        for (uint256 i = 0; i < 5; i++) {
            if (outMessages[i].info.dest.hash == bytes32(uint256(0xc0470ccf))) {
                uint256 idx = outMessages[i].bodyIdx;
                data.eth_address = address(uint160(readUint(cells, idx, 160)));
                data.amount = readUint64(cells, idx, 64);
            }
        }

        return data;
    }

    function parseMessage(CellData[100] memory cells, uint256 messagesIdx)
        public
        view
        returns (Message memory message)
    {
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

        message.bodyIdx = readBool(cells, messagesIdx)
            ? readCell(cells, messagesIdx)
            : messagesIdx;

        return message;
    }

    function parseCommonMsgInfo(CellData[100] memory cells, uint256 messagesIdx)
        public
        view
        returns (RawCommonMessageInfo memory msgInfo)
    {
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

    function readAddress(CellData[100] memory cells, uint256 messagesIdx)
        public
        pure
        returns (TonAddress memory addr)
    {
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

    function deserialize(bytes calldata boc)
        public
        view
        returns (TransactionHeader memory transaction)
    {
        BagOfCellsInfo memory info = parse_serialized_header(boc);

        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[100] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint256 rootIdx = info.cell_count -
            read_int(boc[info.roots_offset:], info.ref_byte_size) -
            1;

        CellData[100] memory cells = get_tree_of_cells(boc, info);

        // for (uint i = 0; i < 100; i++) {
        //     console.logBytes(cells[i].bits);
        //     console.log("==============");
        // }
        // console.logBytes32(cells[rootIdx]._hash);

        transaction = parseTransactionHeader(cells, rootIdx);
        transaction.messages = parseMessagesHeader(
            cells,
            readCell(cells, rootIdx)
        );

        return transaction;
    }

    function deserializeMsgData(bytes calldata boc)
        public
        view
        returns (TestData memory data)
    {
        BagOfCellsInfo memory info = parse_serialized_header(boc);

        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[100] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint256 rootIdx = info.cell_count -
            read_int(boc[info.roots_offset:], info.ref_byte_size) -
            1;

        CellData[100] memory cells = get_tree_of_cells(boc, info);

        parseTransactionHeader(cells, rootIdx);
        MessagesHeader memory messages = parseMessagesHeader(
            cells,
            readCell(cells, rootIdx)
        );

        return getDataFromMessages(cells, messages.outMessages);
    }

    function readBit(CellData[100] memory cells, uint256 cellIdx)
        public
        pure
        returns (uint8 value)
    {
        uint256 cursor = cells[cellIdx].cursor / 8;
        uint256 bytesStart = cells[cellIdx].cursor % 8;
        value = uint8((cells[cellIdx].bits[cursor] << bytesStart) >> 7);
        cells[cellIdx].cursor += 1;
        return value;
    }

    function readBool(CellData[100] memory cells, uint256 cellIdx)
        public
        pure
        returns (bool value)
    {
        return readBit(cells, cellIdx) == 1;
    }

    function readUint8(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public pure returns (uint8 value) {
        require(size <= 8, "max size is 8 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint16(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public view returns (uint16 value) {
        require(size <= 16, "max size is 16 bits");
        value = 0;
        // console.log("readUint16 start");
        while (size > 0) {
            // console.log("read", size);
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }
        // console.log("readUint16 end");

        return value;
    }

    function readUint32(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint8 size
    ) public pure returns (uint32 value) {
        require(size <= 32, "max size is 32 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint64(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint16 size
    ) public pure returns (uint64 value) {
        require(size <= 64, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readUint(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint16 size
    ) public pure returns (uint256 value) {
        require(size <= 256, "max size is 64 bits");
        value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }

        return value;
    }

    function readBytes32_2(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 size
    ) public pure returns (bytes32 buffer) {
        uint256 value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readBytes32(
        CellData[100] memory cells,
        uint256 cellIdx,
        uint256 sizeb
    ) public pure returns (bytes32 buffer) {
        uint256 size = sizeb * 8;
        uint256 value = 0;
        while (size > 0) {
            value = (value << 1) + readBit(cells, cellIdx);
            size--;
        }
        buffer = bytes32(value);
        return buffer;
    }

    function readCell(CellData[100] memory cells, uint256 cellIdx)
        public
        pure
        returns (uint256 idx)
    {
        idx = cells[cellIdx].refs[cells[cellIdx].cursorRef];
        cells[cellIdx].cursorRef++;
        return idx;
    }

    function readUnaryLength(CellData[100] memory cells, uint256 cellIdx)
        public
        pure
        returns (uint256 value)
    {
        value = 0;
        while (readBool(cells, cellIdx)) {
            value++;
        }
        return value;
    }

    function log2Ceil(uint256 x) public pure returns (uint256 n) {
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

    function get_tree_of_cells(bytes calldata boc, BagOfCellsInfo memory info)
        public
        view
        returns (CellData[100] memory cells)
    {
        uint256[100] memory custom_index = get_indexes(boc, info);

        bytes calldata cells_slice = boc[info.data_offset:info.data_offset +
            info.data_size];

        uint256 idx;
        for (uint256 i = 0; i < info.cell_count; i++) {
            idx = info.cell_count - 1 - i;
            cells[i] = deserialize_cell(
                idx,
                cells_slice,
                custom_index,
                info.ref_byte_size,
                info.cell_count
            );

            bytes calldata cell_slice = get_cell_slice(
                idx,
                cells_slice,
                custom_index
            );
            CellSerializationInfo
                memory cell_info = init_cell_serialization_info(
                    cell_slice,
                    info.ref_byte_size
                );

            cells[i].cellType = OrdinaryCell;

            if (cells[i].special) {
                cells[i].cellType = readUint8(cells, i, 8);
                cells[i].cursor -= 8;
            }

            // console.log("Cell Type:", cells[i].cellType);
            calcHashForRefs(cell_info, cells, i, cell_slice);
            // console.log("Repr of cell: ");
            // console.logBytes(cell_slice);
            // console.logBytes32(cells[i]._hash[0]);
            // console.logBytes32(cells[i]._hash[1]);
        }
        return cells;
    }

    function calcHashForRefs(
        CellSerializationInfo memory cell_info,
        CellData[100] memory cells,
        uint256 i,
        bytes calldata cell_slice
    ) public view {
        uint8 hash_i_offset = getHashesCount(cell_info.level_mask) -
            (
                cells[i].cellType == PrunnedBranchCell
                    ? 1
                    : getHashesCount(cell_info.level_mask)
            );
        uint8 hash_i = 0;
        uint8 level = getLevel(cell_info.level_mask);
        for (uint8 level_i = 0; level_i <= level; level_i++) {
            if (!isLevelSignificant(level_i, cell_info.level_mask)) {
                continue;
            }

            if (hash_i < hash_i_offset) {
                hash_i++;
                continue;
            }

            bytes memory _hash;

            if (hash_i == hash_i_offset) {
                // uint32 new_level_mask = applyLevelMask(level_i);
                require(
                    !(hash_i != 0 && cells[i].cellType != PrunnedBranchCell),
                    "Cannot deserialize cell"
                );
                _hash = cell_slice[:cell_info.refs_offset];
                // console.logBytes(_hash);
            } else {
                require(
                    !(level_i == 0 || cells[i].cellType == PrunnedBranchCell),
                    "Cannot deserialize cell 2"
                );
                _hash = bytes.concat(
                    _hash,
                    cells[i]._hash[hash_i - hash_i_offset - 1]
                );
            }

            // uint8 dest_i = hash_i - hash_i_offset;
            if (cells[i].refs[0] != 255) {
                for (uint256 j = 0; j < 4; j++) {
                    if (cells[i].refs[j] == 255) {
                        break;
                    }
                    // uint16 childDepth = getDepth(level_i, cell_info.level_mask, cells[i].cellType, cells, cells[i].refs[j]);

                    // console.log("child depth:", childDepth);
                    // _hash = bytes.concat(_hash, abi.encodePacked(childDepth));
                    // if (childDepth > cells[i].depth[dest_i]) {
                    //     cells[i].depth[dest_i] = childDepth;
                    // }

                    // uint16 childDepth = getDepth(level_i, cell_info.level_mask, cells[i].cellType, cells, cells[i].refs[j]);

                    // console.log("child depth:", getDepth(level_i, cell_info.level_mask, cells[i].cellType, cells, cells[i].refs[j]));
                    _hash = bytes.concat(
                        _hash,
                        abi.encodePacked(
                            getDepth(
                                level_i,
                                cells[cells[i].refs[j]].level_mask,
                                cells[cells[i].refs[j]].cellType,
                                cells,
                                cells[i].refs[j]
                            )
                        )
                    );
                    if (
                        getDepth(
                            level_i,
                            cells[cells[i].refs[j]].level_mask,
                            cells[cells[i].refs[j]].cellType,
                            cells,
                            cells[i].refs[j]
                        ) > cells[i].depth[hash_i - hash_i_offset]
                    ) {
                        cells[i].depth[hash_i - hash_i_offset] = getDepth(
                            level_i,
                            cells[cells[i].refs[j]].level_mask,
                            cells[cells[i].refs[j]].cellType,
                            cells,
                            cells[i].refs[j]
                        );
                    }
                }

                cells[i].depth[hash_i - hash_i_offset]++;
                // console.logBytes(_hash);
                for (uint256 j = 0; j < 4; j++) {
                    if (cells[i].refs[j] == 255) {
                        break;
                    }
                    // console.log("LEVEL I:", level_i);
                    _hash = bytes.concat(
                        _hash,
                        getHash(
                            level_i,
                            cells[cells[i].refs[j]].level_mask,
                            cells[cells[i].refs[j]].cellType,
                            cells,
                            cells[i].refs[j]
                        )
                    );
                }
                // console.logBytes(_hash);
                cells[i]._hash[hash_i - hash_i_offset] = sha256(_hash);
            } else {
                // console.log("WORING HARD WITHOUT REFS");
                cells[i]._hash[hash_i - hash_i_offset] = sha256(_hash);
            }

            hash_i++;
        }
    }

    function get_indexes(bytes calldata boc, BagOfCellsInfo memory info)
        public
        pure
        returns (uint256[100] memory custom_index)
    {
        require(!info.has_index, "has index logic has not realised");

        bytes calldata cells_slice_for_indexes = boc[info.data_offset:info
            .data_offset + info.data_size];

        uint256 cur = 0;
        for (uint256 i = 0; i < info.cell_count; i++) {
            CellSerializationInfo
                memory cellInfo = init_cell_serialization_info(
                    cells_slice_for_indexes,
                    info.ref_byte_size
                );
            cells_slice_for_indexes = cells_slice_for_indexes[cellInfo
                .end_offset:];
            cur += cellInfo.end_offset;
            custom_index[i] = cur;
        }

        return custom_index;
    }

    function init_cell_serialization_info(
        bytes calldata data,
        uint256 ref_byte_size
    ) public pure returns (CellSerializationInfo memory cellInfo) {
        require(!(data.length < 2), "Not enough bytes");
        uint8 d1 = uint8(data[0]);
        uint8 d2 = uint8(data[1]);

        cellInfo.refs_cnt = d1 & 7;
        cellInfo.level_mask = d1 >> 5;
        cellInfo.special = (d1 & 8) != 0;

        cellInfo.with_hashes = (d1 & 16) != 0;

        if (cellInfo.refs_cnt > 4) {
            require(
                !(cellInfo.refs_cnt != 7 || !cellInfo.with_hashes),
                "Invalid first byte"
            );
            cellInfo.refs_cnt = 0;
            require(false, "TODO: absent cells");
        }

        cellInfo.hashes_offset = 2;
        uint256 n = count_setbits(cellInfo.level_mask) + 1;
        cellInfo.depth_offset =
            cellInfo.hashes_offset +
            (cellInfo.with_hashes ? n * 32 : 0);
        cellInfo.data_offset =
            cellInfo.depth_offset +
            (cellInfo.with_hashes ? n * 2 : 0);
        cellInfo.data_len = (d2 >> 1) + (d2 & 1);
        cellInfo.data_with_bits = (d2 & 1) != 0;
        cellInfo.refs_offset = cellInfo.data_offset + cellInfo.data_len;
        cellInfo.end_offset =
            cellInfo.refs_offset +
            cellInfo.refs_cnt *
            ref_byte_size;

        require(!(data.length < cellInfo.end_offset), "Not enough bytes");
        return cellInfo;
    }

    // instead of get_hashes_count()
    function count_setbits(uint32 n) public pure returns (uint256 cnt) {
        cnt = 0;
        while (n > 0) {
            cnt += n & 1;
            n = n >> 1;
        }
        return cnt;
    }

    function deserialize_cell(
        uint256 idx,
        bytes calldata cells_slice,
        uint256[100] memory custom_index,
        uint256 ref_byte_size,
        uint256 cell_count
    ) public view returns (CellData memory cell) {
        bytes calldata cell_slice = get_cell_slice(
            idx,
            cells_slice,
            custom_index
        );

        uint256[4] memory refs;
        for (uint256 i = 0; i < 4; i++) {
            refs[i] = 255;
        }
        CellSerializationInfo memory cell_info = init_cell_serialization_info(
            cell_slice,
            ref_byte_size
        );
        require(
            !(cell_info.end_offset != cell_slice.length),
            "unused space in cell"
        );

        for (uint256 k = 0; k < cell_info.refs_cnt; k++) {
            uint256 ref_idx = read_int(
                cell_slice[cell_info.refs_offset + k * ref_byte_size:],
                ref_byte_size
            );
            require(!(ref_idx <= idx), "bag-of-cells error");
            require(!(ref_idx >= cell_count), "refIndex is bigger cell count");
            refs[k] = cell_count - ref_idx - 1;
        }

        cell = create_data_cell(cell_slice, refs, cell_info);
        // if (refs[0] == 255) {
        //     cell._hash = cell_hash(cell_slice);
        // }
        // else {
        //     cell._hash = bytes32(cell_slice);
        // }

        cell.level_mask = cell_info.level_mask;
        return cell;
    }

    function get_cell_slice(
        uint256 idx,
        bytes calldata cells_slice,
        uint256[100] memory custom_index
    ) public pure returns (bytes calldata cell_slice) {
        uint256 offs = idx == 0 ? 0 : custom_index[idx - 1];
        uint256 offs_end = custom_index[idx];
        return cells_slice[offs:offs_end];
    }

    function create_data_cell(
        bytes calldata cell_slice,
        uint256[4] memory refs,
        CellSerializationInfo memory cell_info
    ) public pure returns (CellData memory cell) {
        // uint bits = get_bits(cell_slice, cell_info);
        bytes calldata bits_slice = cell_slice[cell_info.data_offset:];
        cell.bits = bits_slice;
        cell.refs = refs;
        cell.cursor = 0;
        cell.special = cell_info.special;
        cell.cursorRef = 0;
        return cell;
    }

    function get_bits(
        bytes calldata cell,
        CellSerializationInfo memory cell_info
    ) public pure returns (uint256) {
        if (cell_info.data_with_bits) {
            require((cell_info.data_len != 0), "no data in cell");
            uint32 last = uint8(
                cell[cell_info.data_offset + cell_info.data_len - 1]
            );
            // require(!(!(last & 0x7f)), "overlong encoding");
            return ((cell_info.data_len - 1) *
                8 +
                7 -
                count_trailing_zeroes_non_zero32(last));
        } else {
            return cell_info.data_len * 8;
        }
    }

    function count_trailing_zeroes_non_zero32(uint32 n)
        public
        pure
        returns (uint256)
    {
        uint256 bits = 0;
        uint256 x = n;

        if (x > 0) {
            while ((x & 1) == 0) {
                ++bits;
                x >>= 1;
            }
        }

        return bits;
    }

    function read_int(bytes calldata data, uint256 size)
        public
        pure
        returns (uint256 value)
    {
        uint256 res = 0;
        uint256 cursor = 0;
        while (size > 0) {
            res = (res << 8) + uint8(data[cursor]);
            cursor++;
            --size;
        }
        return res;
    }

    // // function getMaxLevel(CellData[100] memory cells, uint cellIdx) public pure returns (uint8 maxLevel) {
    // //     //TODO level calculation differ for exotic cells
    // //     maxLevel = 0;
    // //     for (uint8 i = 0; i < 4; i++) {
    // //         if (cells[cellIdx].refs[i] != 255) {
    // //             uint8 nMaxLevel = getMaxLevel(cells, cells[cellIdx].refs[i]);
    // //             if (nMaxLevel > maxLevel) {
    // //                 maxLevel = nMaxLevel;
    // //             }
    // //         }
    // //     }
    // //     return maxLevel;
    // // }

    function cell_hash(bytes calldata cell) public pure returns (bytes32) {
        // uint8 refsLength = 0;
        // for (uint8 i = 0; i < 4; i++) {
        //     if (cells[cellIdx].refs[i] != 255) {
        //         refsLength++;
        //     }
        // }
        // uint8 d1 = refsLength + (cells[cellIdx].special ? 8 : 0) + getMaxLevel(cells, cellIdx) * 32;
        // uint8 d2 =  cells[cellIdx].cursor % 8 + cells[cellIdx].cursor / 8;
        // // special * 8

        return sha256(cell);
    }

    function applyLevelMask(uint8 level, uint32 levelMask)
        public
        view
        returns (uint32 f)
    {
        f = uint32(levelMask & ((1 << level) - 1));
        // console.log("Apply levelmask work", f);
        return f;
    }

    function getLevelFromMask(uint32 mask) public pure returns (uint8 n) {
        n = 0;
        uint32 maskCopy = mask;
        for (uint8 i = 0; i < 3; i++) {
            n += uint8(maskCopy & 1);
            maskCopy = maskCopy >> 1;
        }
        return n + 1;
    }

    function getLevel(uint32 mask) public pure returns (uint8 n) {
        return getLevelFromMask(mask & 7);
    }

    function getHashesCountFromMask(uint32 mask) public view returns (uint8) {
        // console.log("get Hashes Count From Mask work");
        uint8 n = 0;
        uint32 maskCopy = mask;
        for (uint8 i = 0; i < 3; i++) {
            n += uint8(maskCopy & 1);
            maskCopy = maskCopy >> 1;
        }
        return n + 1;
    }

    function getHashesCount(uint32 mask) public view returns (uint8) {
        return getHashesCountFromMask(mask & 7);
    }

    function getHash(
        uint8 level,
        uint32 levelMask,
        uint256 cellType,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public view returns (bytes32) {
        uint8 hash_i = getHashesCountFromMask(
            applyLevelMask(level, levelMask)
        ) - 1;
        // console.log("HASH_I:", hash_i);
        if (cellType == PrunnedBranchCell) {
            // console.log("Is pruned");
            uint8 this_hash_i = getHashesCount(levelMask) - 1;
            // console.log("Got data from bits", this_hash_i, hash_i);
            if (hash_i != this_hash_i) {
                uint256 cursor = 16 + uint256(hash_i) * 2 * 8;
                uint256 hash_num = readUint(cells, cellIdx, 256);
                cells[cellIdx].cursor -= cursor;

                return bytes32(hash_num);
            }
            hash_i = 0;
        }
        return cells[cellIdx]._hash[hash_i];
    }

    function isLevelSignificant(uint8 level, uint32 mask)
        public
        pure
        returns (bool)
    {
        return (level == 0) || ((mask >> (level - 1)) % 2 != 0);
    }

    function getDepth(
        uint8 level,
        uint32 mask,
        uint256 cellType,
        CellData[100] memory cells,
        uint256 cellIdx
    ) public view returns (uint16) {
        // console.log("GET DEPTH WORK");
        uint32 levelMask = applyLevelMask(level, mask);

        uint8 hash_i = getHashesCountFromMask(levelMask) - 1;
        // console.log("HASH_I:", hash_i);
        if (cellType == PrunnedBranchCell) {
            // console.log("Is pruned");
            uint8 this_hash_i = getHashesCount(mask) - 1;
            if (hash_i != this_hash_i) {
                uint256 cursor = 16 +
                    uint256(this_hash_i) *
                    32 *
                    8 +
                    uint256(hash_i) *
                    2 *
                    8;
                cells[cellIdx].cursor = cursor;
                uint16 childDepth = readUint16(cells, cellIdx, 16);
                // console.log("Got data from bits", this_hash_i, hash_i, childDepth);
                cells[cellIdx].cursor -= cursor;

                return childDepth;
            }
            hash_i = 0;
        }
        return cells[cellIdx].depth[hash_i];
    }

    function parse_block(
        bytes calldata proofBoc,
        BagOfCellsInfo memory proofBocInfo,
        CellData[100] memory proofTreeOfCells,
        bytes32 txRootHash
    ) public view returns (bool) {
        uint256 proofRootIdx = proofBocInfo.cell_count -
            read_int(
                proofBoc[proofBocInfo.roots_offset:],
                proofBocInfo.ref_byte_size
            ) -
            1;

        uint32 tag = readUint32(proofTreeOfCells, proofRootIdx, 32);
        console.log("GlobalId?:", tag);
        // blockInfo? (pruned)
        readCell(proofTreeOfCells, proofRootIdx);
        // value flow? (pruned)
        readCell(proofTreeOfCells, proofRootIdx);
        // state_update? (pruned)
        readCell(proofTreeOfCells, proofRootIdx);
        uint256 extraIdx = readCell(proofTreeOfCells, proofRootIdx);
        console.log("extra id", extraIdx);
        return parse_block_extra(proofTreeOfCells, extraIdx, txRootHash);
        //return proofTreeOfCells[proofRootIdx];
    }

    function parse_block_extra(
        CellData[100] memory cells,
        uint256 cellIdx,
        bytes32 txRootHash
    ) public view returns (bool) {
        uint32 isBlockExtra = readUint32(cells, cellIdx, 32);
        require(isBlockExtra == 1244919549, "cell is not extra block info");

        // in pruned block cells with extra block data reverted
        // in_msg_descr? (pruned)
        uint256 in_msg_descr = readCell(cells, cellIdx);
        // out_msg_descr? (pruned)
        // readCell(cells, cellIdx);
        // account_blocks?
        // uint256 account_blocksIdx = readCell(cells, readCell(cells, cellIdx));
        // console.log("account_blocksIdx", account_blocksIdx);

        in_msg_descr = readCell(cells, in_msg_descr);

        uint256[10] memory inMsgIdxs = parseDict(
            cells,
            // account_blocksIdx,
            in_msg_descr,
            256
        );
        for (uint256 i = 0; i < 10; i++) {
            if (inMsgIdxs[i] == 255) {
                break;
            }
            // cells[inMsgIdxs[i]].cursor = 292;

            // console.log("IN MSG TYPE CHECK", cells[inMsgIdxs[i]].cursor, inMsgType);
            // console.log(accountIdxs[i]);
            // console.logBytes(cells[accountIdxs[i]].bits);
            // console.log(
            //     "cursor",
            //     cells[inMsgIdxs[i]].cursor,
            //     cells[inMsgIdxs[i]].cursor / 8,
            //     cells[inMsgIdxs[i]].bits.length
            // );
            // cells[accountIdxs[i]].cursor += 12; // 7 is so good
            // console.log("isAccountBlock", readUint8(cells, accountIdxs[i], 4), cells[accountIdxs[i]].cursor);
            // bytes32 addressHash = readBytes32(cells, accountIdxs[i], 32);
            // console.log("Block account");
            // console.logBytes32(addressHash);
            // get transactions of this account
            // uint256[10] memory txIdxs = parseDict(cells, inMsgIdxs[i], 4 /* 64 */);
            // for (uint j = 0; j < 10; j++) {
            //     console.log(txIdxs[j]);
            // }

            /*
            
            msg_import_ext$000 msg:^(Message Any) transaction:^Transaction 
              = InMsg;
            
            import_fees$_ fees_collected:Grams 
            value_imported:CurrencyCollection = ImportFees;
            */
            parseCurrencyCollection(cells, inMsgIdxs[i]);
            uint8 inMsgType = readUint8(cells, inMsgIdxs[i], 3);
            console.log(
                "IN MSG TYPE CHECK",
                cells[inMsgIdxs[i]].cursor,
                inMsgType
            );
            require(inMsgType == 0, "Wrong msg type");
            uint256 transactionCellIdx = cells[inMsgIdxs[i]].refs[1];
            if (cells[transactionCellIdx]._hash[0] == txRootHash) {
                return true;
            }
        }
        return false;
    }

    function proofTx(bytes calldata txBoc, bytes calldata proofBoc)
        public
        view
        returns (bool)
    {
        BagOfCellsInfo memory txBocInfo = parse_serialized_header(txBoc);
        BagOfCellsInfo memory proofBocInfo = parse_serialized_header(proofBoc);
        uint256 txRootIdx = txBocInfo.cell_count -
            read_int(txBoc[txBocInfo.roots_offset:], txBocInfo.ref_byte_size) -
            1;
        CellData[100] memory txTreeOfCells = get_tree_of_cells(
            txBoc,
            txBocInfo
        );
        CellData[100] memory proofTreeOfCells = get_tree_of_cells(
            proofBoc,
            proofBocInfo
        );

        // TransactionHeader memory transaction = parseTransactionHeader(
        //     txTreeOfCells,
        //     txRootIdx
        // );
        // console.log("Tx addr hash");
        // console.logBytes32(transaction.addressHash);

        return
            parse_block(
                proofBoc,
                proofBocInfo,
                proofTreeOfCells,
                txTreeOfCells[txRootIdx]._hash[0]
            );
        // for(uint i = 0; i < 100; i++) {
        //     if (proofTreeOfCells[i].cellType == 0) {
        //         break;
        //     }
        //     if (proofTreeOfCells[i]._hash[0] == txTreeOfCells[txRootIdx]._hash[0]) {
        //         return true;
        //     }
        // }
        // return false;
        // return proofTreeOfCells;
    }
}
