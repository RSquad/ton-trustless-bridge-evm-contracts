use cosmwasm_schema::{cw_serde, QueryResponses};
use cosmwasm_std::{Addr, HexBinary};
use tonbridge_parser::types::VdataHex;

#[cw_serde]
pub struct InstantiateMsg {
    pub boc: Option<HexBinary>,
}

#[cw_serde]
pub enum ExecuteMsg {
    UpdateOwner {
        new_owner: Addr,
    },
    PrepareNewKeyBlock {
        keyblock_boc: HexBinary, // in hex form
    },
    ResetValidatorSet {
        boc: HexBinary,
    },
    VerifyKeyBlock {
        root_hash: HexBinary, // in hex form
        file_hash: HexBinary, // in hex form
        vdata: Vec<VdataHex>,
    },
    VerifyMasterchainBlockByValidatorSignatures {
        block_header_proof: HexBinary,
        file_hash: HexBinary,
        vdata: Vec<VdataHex>,
    },
    VerifyShardBlocks {
        shard_proof_links: Vec<HexBinary>, // in hex form
        mc_block_root_hash: HexBinary,
    },
    SetVerifiedBlock {
        root_hash: HexBinary,
        seq_no: u32,
    },
}

/// We currently take no arguments for migrations
#[cw_serde]
pub struct MigrateMsg {}

#[cw_serde]
#[derive(QueryResponses)]
pub enum QueryMsg {
    #[returns(ConfigResponse)]
    Config {},
    #[returns(Vec<UserFriendlyValidator>)]
    GetCandidatesForValidators {
        start_after: Option<u64>,
        limit: Option<u32>,
        order: Option<u8>,
    },
    #[returns(Vec<UserFriendlyValidator>)]
    GetValidators {
        start_after: Option<String>,
        limit: Option<u32>,
        order: Option<u8>,
    },
    #[returns(bool)]
    IsVerifiedBlock { root_hash: HexBinary }, // in hex form
    #[returns(bool)]
    IsSignedByValidator {
        validator_node_id: HexBinary,
        root_hash: HexBinary,
    },
    #[returns(bool)]
    NextValidatorUpdated {},
}

// We define a custom struct for each query response
#[cw_serde]
pub struct ConfigResponse {
    pub owner: Option<String>,
}

#[cw_serde]
pub struct UserFriendlyValidator {
    pub c_type: u8,
    pub weight: u64,
    pub adnl_addr: HexBinary,
    pub pubkey: HexBinary,  // in hex form
    pub node_id: HexBinary, // in hex form
}
