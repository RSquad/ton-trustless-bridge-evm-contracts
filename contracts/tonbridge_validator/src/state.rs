use cosmwasm_std::{HexBinary, Order, StdResult, Storage};
use cw_storage_plus::{Index, IndexList, IndexedMap, Item, Map, MultiIndex};

use cw_controllers::Admin;
use tonbridge_parser::types::{Bytes32, ValidatorDescription, VerifiedBlockInfo};

use crate::validator::Validator;

/// Owner admin
pub const OWNER: Admin = Admin::new("owner");
pub const SIGNED_BLOCKS: Map<&[u8], bool> = Map::new("signed_blocks");
pub const VERIFIED_BLOCKS: Map<&Bytes32, VerifiedBlockInfo> = Map::new("verified_blocks");

pub const VALIDATOR: Item<Validator> = Item::new("validator");
pub const SIGNATURE_CANDIDATE_VALIDATOR: Map<u64, ValidatorDescription> =
    Map::new("signature_candidate_validator");

pub struct ValidatorSetIndexes<'a> {
    pub pubkey: MultiIndex<'a, String, ValidatorDescription, String>,
}

// IndexList is just boilerplate code for fetching a struct's indexes
impl<'a> IndexList<ValidatorDescription> for ValidatorSetIndexes<'a> {
    fn get_indexes(&'_ self) -> Box<dyn Iterator<Item = &'_ dyn Index<ValidatorDescription>> + '_> {
        let v: Vec<&dyn Index<ValidatorDescription>> = vec![&self.pubkey];
        Box::new(v.into_iter())
    }
}

pub fn validator_set<'a>() -> IndexedMap<'a, &'a [u8], ValidatorDescription, ValidatorSetIndexes<'a>>
{
    let indexes = ValidatorSetIndexes {
        pubkey: MultiIndex::new(
            |_k, d| HexBinary::from(d.pubkey).to_hex(),
            "validator_set_namespace",
            "pubkey",
        ),
    };
    IndexedMap::new("validator_set_namespace", indexes)
}

pub fn get_signature_candidate_validators(
    storage: &dyn Storage,
) -> StdResult<Vec<ValidatorDescription>> {
    SIGNATURE_CANDIDATE_VALIDATOR
        .range_raw(storage, None, None, Order::Ascending)
        .map(|item| item.map(|item| item.1))
        .collect()
}

pub fn get_signature_validator_set(storage: &dyn Storage) -> StdResult<Vec<ValidatorDescription>> {
    validator_set()
        .range_raw(storage, None, None, Order::Ascending)
        .map(|item| item.map(|item| item.1))
        .collect()
}

pub fn reset_signature_candidate_validators(storage: &mut dyn Storage) {
    SIGNATURE_CANDIDATE_VALIDATOR.clear(storage);
}

pub fn reset_signature_validator_set(storage: &mut dyn Storage) {
    validator_set().clear(storage);
}
