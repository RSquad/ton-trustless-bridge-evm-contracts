// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.5 <0.9.0;
pragma experimental ABIEncoderV2;

import "../libraries/Ed25519.sol";

contract TestEd25519 {
    function verify(
        bytes32 k,
        bytes32 r,
        bytes32 s,
        bytes memory m
    ) public view returns (bool) {
        return Ed25519.verify(k, r, s, m);
    }
}
