//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct CellData {
    bool special;
    uint[4] refs;
    uint cursor;
    uint8 cursorRef;

    bytes32[4] _hash;
    uint32 level_mask;
    uint16[4] depth;
    uint8 cellType;
}