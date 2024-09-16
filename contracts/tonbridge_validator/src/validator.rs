use cosmwasm_schema::cw_serde;
use cosmwasm_std::{attr, Addr, Api, Attribute, DepsMut, HexBinary, StdError, StdResult, Storage};
use tonbridge_parser::{
    to_bytes32,
    types::{Bytes32, ValidatorDescription, ValidatorSet, Vdata, VerifiedBlockInfo},
    EMPTY_HASH,
};
use tonbridge_validator::msg::UserFriendlyValidator;
use tonlib::cell::BagOfCells;

use crate::{
    error::ContractError,
    signature_validator::{ISignatureValidator, SignatureValidator},
    state::{
        get_signature_candidate_validators, get_signature_validator_set, OWNER, VERIFIED_BLOCKS,
    },
};

pub trait IValidator {
    fn is_verified_block(&self, storage: &dyn Storage, root_hash: Bytes32) -> StdResult<bool>;
}

#[cw_serde]
#[derive(Default)]
pub struct Validator {
    pub signature_validator: SignatureValidator,
}

impl Validator {
    pub fn is_signed_by_validator(
        &self,
        storage: &dyn Storage,
        node_id: Bytes32,
        root_h: Bytes32,
    ) -> bool {
        self.signature_validator
            .is_signed_by_validator(storage, node_id, root_h)
    }

    pub fn get_validators(&self, storage: &dyn Storage) -> StdResult<ValidatorSet> {
        //  self.signature_validator.validator_set.to_owned()
        get_signature_validator_set(storage)
    }

    pub fn get_candidates_for_validators(&self, storage: &dyn Storage) -> StdResult<ValidatorSet> {
        // self.signature_validator
        //     .candidates_for_validator_set
        //     .to_owned()
        get_signature_candidate_validators(storage)
    }

    pub fn next_validator_updated(&self) -> bool {
        self.signature_validator.has_next
    }

    pub fn parse_candidates_root_block(
        &mut self,
        storage: &mut dyn Storage,
        boc: &[u8],
    ) -> Result<(), ContractError> {
        self.signature_validator
            .parse_candidates_root_block(storage, boc)?;
        Ok(())
    }

    pub fn init_validators(&mut self, storage: &mut dyn Storage) -> StdResult<()> {
        let key_block_root_hash = self.signature_validator.init_validators(storage)?;
        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            ..Default::default()
        };

        VERIFIED_BLOCKS.save(storage, &key_block_root_hash, &verified_block_info)
    }

    pub fn set_validator_set(&mut self, storage: &mut dyn Storage, api: &dyn Api) -> StdResult<()> {
        let key_block_root_hash = self.signature_validator.set_validator_set(storage, api)?;
        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            ..Default::default()
        };
        VERIFIED_BLOCKS.save(storage, &key_block_root_hash, &verified_block_info)
    }

    pub fn verify_validators(
        &self,
        storage: &mut dyn Storage,
        api: &dyn Api,
        root_h: Bytes32,
        file_hash: Bytes32,
        vdata: &[Vdata],
    ) -> StdResult<()> {
        let test_root_hash = if self.signature_validator.root_hash == EMPTY_HASH {
            root_h
        } else {
            self.signature_validator.root_hash
        };
        self.signature_validator.verify_validators(
            storage,
            api,
            test_root_hash,
            file_hash,
            vdata,
        )?;
        Ok(())
    }

    pub fn verify_masterchain_block_by_validator_signatures(
        &self,
        storage: &mut dyn Storage,
        api: &dyn Api,
        block_header_proof: HexBinary,
        file_hash: Bytes32,
        vdata: &[Vdata],
    ) -> Result<HexBinary, ContractError> {
        let block_header_proof = BagOfCells::parse(block_header_proof.as_slice())?;
        let root_hash_from_block_header = block_header_proof.root(0)?.reference(0)?.get_hash(0);
        let current_weight = self.signature_validator.verify_validators(
            storage,
            api,
            root_hash_from_block_header.as_slice().try_into()?,
            file_hash,
            vdata,
        )?;

        if current_weight * 3 <= self.signature_validator.sum_largest_total_weights * 2 {
            return Err(ContractError::Std(StdError::generic_err(format!(
                "not enough votes to verify block. Wanted {:?}; has {:?}",
                self.signature_validator.sum_largest_total_weights * 2,
                current_weight * 3,
            ))));
        }

        let verified_block_info = VerifiedBlockInfo {
            verified: true,
            ..Default::default()
        };

        VERIFIED_BLOCKS.save(
            storage,
            root_hash_from_block_header.as_slice().try_into()?,
            &verified_block_info,
        )?;
        Ok(HexBinary::from(root_hash_from_block_header))
    }

    pub fn verify_shard_blocks(
        &self,
        storage: &mut dyn Storage,
        shard_proof_links: Vec<HexBinary>,
        mc_block_root_hash: HexBinary,
    ) -> Result<Vec<Attribute>, ContractError> {
        if !self.is_verified_block(storage, to_bytes32(&mc_block_root_hash)?)? {
            return Err(ContractError::Std(StdError::generic_err(
                "masterchain block root hash is not verified",
            )));
        }
        let mut attrs: Vec<Attribute> = vec![];
        for (i, proof_link) in shard_proof_links.iter().enumerate() {
            let cells = BagOfCells::parse(proof_link.as_slice())?;

            let root = cells.single_root()?;
            let first_ref = root.reference(0)?;
            let block = first_ref.load_block()?;
            let merkle_proof_root_hash = first_ref.get_hash(0);
            if i == 0 {
                if merkle_proof_root_hash.ne(&mc_block_root_hash.to_vec()) {
                    return Err(ContractError::Std(StdError::generic_err(
                        "merkle proof not verified",
                    )));
                }
                if block.extra.is_none() {
                    return Err(ContractError::Std(StdError::generic_err(
                        "There is no shard included in this masterchain block to verify.",
                    )));
                }
                let extra = block.extra.unwrap().custom.shards;
                for shards in extra.values() {
                    for shard in shards {
                        let verified_block = VerifiedBlockInfo {
                            verified: true,
                            seq_no: shard.seqno,
                            start_lt: shard.start_lt,
                            end_lt: shard.end_lt,
                            ..Default::default()
                        };

                        VERIFIED_BLOCKS.save(
                            storage,
                            shard.root_hash.as_slice().try_into()?,
                            &verified_block,
                        )?;
                        attrs.push(attr(
                            "root_hash",
                            HexBinary::from(shard.root_hash.clone()).to_hex(),
                        ));
                    }
                }
            } else {
                if !self
                    .is_verified_block(storage, merkle_proof_root_hash.as_slice().try_into()?)?
                {
                    return Err(ContractError::Std(StdError::generic_err(
                        "The shard block root hash is not verified",
                    )));
                }
                if block.info.is_none() {
                    return Err(ContractError::Std(StdError::generic_err(
                        "There is no shard block info to collect prev block hash from.",
                    )));
                }
                let prev_ref = block.info.unwrap().prev_ref;
                if let Some(prev_blk) = prev_ref.first_prev {
                    let verified_block = VerifiedBlockInfo {
                        verified: true,
                        seq_no: prev_blk.seqno,
                        end_lt: prev_blk.end_lt,
                        ..Default::default()
                    };

                    VERIFIED_BLOCKS.save(
                        storage,
                        prev_blk.root_hash.as_slice().try_into()?,
                        &verified_block,
                    )?;
                    attrs.push(attr(
                        "root_hash",
                        HexBinary::from(prev_blk.root_hash).to_hex(),
                    ));
                }
                if let Some(prev_blk) = prev_ref.second_prev {
                    let verified_block = VerifiedBlockInfo {
                        verified: true,
                        seq_no: prev_blk.seqno,
                        end_lt: prev_blk.end_lt,
                        ..Default::default()
                    };

                    VERIFIED_BLOCKS.save(
                        storage,
                        prev_blk.root_hash.as_slice().try_into()?,
                        &verified_block,
                    )?;
                    attrs.push(attr(
                        "root_hash",
                        HexBinary::from(prev_blk.root_hash).to_hex(),
                    ));
                }
            }
        }
        Ok(attrs)
    }

    pub fn set_verified_block(
        &self,
        deps_mut: DepsMut,
        caller: &Addr,
        root_hash: Bytes32,
        seq_no: u32,
    ) -> StdResult<()> {
        let deps = deps_mut.as_ref();
        OWNER
            .assert_admin(deps, caller)
            .map_err(|err| StdError::generic_err(err.to_string()))?;
        if self.is_verified_block(deps.storage, root_hash)? {
            return Err(StdError::generic_err("block already verified"));
        }

        let block = VerifiedBlockInfo {
            seq_no,
            verified: true,
            ..Default::default()
        };

        VERIFIED_BLOCKS.save(deps_mut.storage, &root_hash, &block)
    }

    pub fn parse_user_friendly_validator(
        validator_description: ValidatorDescription,
    ) -> UserFriendlyValidator {
        UserFriendlyValidator {
            c_type: validator_description.c_type,
            weight: validator_description.weight,
            adnl_addr: HexBinary::from(&validator_description.adnl_addr),
            pubkey: HexBinary::from(&validator_description.pubkey),
            node_id: HexBinary::from(&validator_description.node_id),
        }
    }

    pub fn parse_user_friendly_validators(
        validator_set: ValidatorSet,
    ) -> Vec<UserFriendlyValidator> {
        validator_set
            .into_iter()
            .map(Validator::parse_user_friendly_validator)
            .collect()
    }
}

impl IValidator for Validator {
    fn is_verified_block(&self, storage: &dyn Storage, root_hash: Bytes32) -> StdResult<bool> {
        Ok(VERIFIED_BLOCKS
            .may_load(storage, &root_hash)?
            .unwrap_or_default()
            .verified)
    }
}
