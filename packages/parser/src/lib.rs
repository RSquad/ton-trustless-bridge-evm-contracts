use crate::types::Bytes32;
use cosmwasm_std::{HexBinary, StdError};
use sha2::{Digest, Sha256};
use std::array::TryFromSliceError;

pub const OPCODE_1: Bytes32 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
];
pub const OPCODE_2: Bytes32 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2,
];

pub const EMPTY_HASH: Bytes32 = [0; 32];

pub fn sha256(data: &[u8]) -> Bytes32 {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

pub fn compute_node_id(public_key: Bytes32) -> Bytes32 {
    let mut data = vec![0xc6, 0xb4, 0x13, 0x48];
    data.extend_from_slice(&public_key);
    sha256(&data)
}

pub fn to_bytes32(hex_bin: &HexBinary) -> Result<Bytes32, StdError> {
    hex_bin
        .as_slice()
        .try_into()
        .map_err(|err: TryFromSliceError| StdError::generic_err(err.to_string()))
}

pub mod transaction_parser;
pub mod types;
