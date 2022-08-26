//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.5 <0.9.0;

struct CellData {
    bool special;
    uint[4] refs;
    uint cursor;
    uint8 cursorRef;
}