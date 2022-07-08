//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

import "hardhat/console.sol";
import "./BocHeaderInfoAdapter.sol";
import "./TreeOfCellsAdapter.sol";
import "./UtilsLib.sol";

struct BagOfCells {
    uint cell_count;    
}



struct RootInfo {
    uint idx;
    CellData root;
}

contract BocHeaderAdapter is BocHeaderInfoAdapter, TreeOfCellsAdapter {

    function deserialize(bytes calldata boc) public view {
        BagOfCellsInfo memory info = parse_serialized_header(boc);
        
        require(info.root_count == 1, "Should have only 1 root");
        // if (info.has_crc32c) {
        //     // TODO
        // }

        // uint8[50] memory cell_should_cache;
        require(!info.has_cache_bits, "has_cache_bits logic has not realised");

        // We have only 1 root, so we don't need to write code for find all root indexes
        uint rootIdx = info.cell_count - UtilsLib.read_int(boc[info.roots_offset:], info.ref_byte_size) - 1;
        console.log("Root idx: %d",rootIdx);
        
        CellData[50] memory cells = get_tree_of_cells(boc, info);
        
        uint data;
        data = read_int_memory(cells[rootIdx].bits, 1, 0) >> 4;
        console.log("prefix: %d", data);
        // addressHash
        data = read_int_memory(cells[rootIdx].bits, 32, 1) >> 4; // взять 4 бита из 0-го байта и дописать в начало
        console.log("addressHash: %d", data);
        // lt
        data = read_int_memory(cells[rootIdx].bits, 10, 31) << 256 - 64 + 4 >> 256 - 64 + 8;
        console.log("lt: %d", data);

    }

    function read_int_memory(bytes memory data, uint size, uint start) public pure returns(uint value) {
        uint res = 0;
        uint cursor = 0;
        while (size > 0) {
            res = (res << 8) + uint8(data[start + cursor]);
            cursor++;
            --size;
        }
        return res;
    }
}