#[cfg(not(feature = "library"))]
use cosmwasm_std::entry_point;

use std::array::TryFromSliceError;

use cosmwasm_std::{to_json_binary, Addr, Empty, HexBinary, Order, StdError};
use cosmwasm_std::{Binary, Deps, DepsMut, Env, MessageInfo, Response, StdResult};
use cw_storage_plus::Bound;
use tonbridge_parser::to_bytes32;
use tonbridge_parser::types::{Vdata, VdataHex};
use tonbridge_validator::msg::{
    ConfigResponse, ExecuteMsg, InstantiateMsg, MigrateMsg, QueryMsg, UserFriendlyValidator,
};

use crate::error::ContractError;
use crate::state::{validator_set, OWNER, SIGNATURE_CANDIDATE_VALIDATOR, VALIDATOR};
use crate::validator::{IValidator, Validator};

// settings for pagination
const MAX_LIMIT: u32 = 100;
const DEFAULT_LIMIT: u32 = 30;

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    msg: InstantiateMsg,
) -> Result<Response, ContractError> {
    let mut validator = Validator::default();
    if let Some(boc) = msg.boc {
        validator.parse_candidates_root_block(deps.storage, boc.as_slice())?;
        validator.init_validators(deps.storage)?;
    }
    VALIDATOR.save(deps.storage, &validator)?;
    OWNER.set(deps, Some(info.sender))?;
    Ok(Response::new())
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> Result<Response, ContractError> {
    match msg {
        ExecuteMsg::UpdateOwner { new_owner } => execute_update_owner(deps, info, new_owner),
        ExecuteMsg::PrepareNewKeyBlock { keyblock_boc } => {
            parse_candidates_root_block(deps, keyblock_boc)
        }
        ExecuteMsg::ResetValidatorSet { boc } => reset_validator_set(deps, &info.sender, boc),
        // ExecuteMsg::SetValidatorSet {} => set_validator_set(deps),
        ExecuteMsg::VerifyKeyBlock {
            root_hash,
            file_hash,
            vdata,
        } => verify_validators(deps, root_hash, file_hash, vdata),
        ExecuteMsg::VerifyMasterchainBlockByValidatorSignatures {
            block_header_proof,
            file_hash,
            vdata,
        } => verify_masterchain_block_by_validator_signatures(
            deps,
            block_header_proof,
            file_hash,
            vdata,
        ),
        ExecuteMsg::VerifyShardBlocks {
            shard_proof_links,
            mc_block_root_hash,
        } => verify_shard_blocks(deps, shard_proof_links, mc_block_root_hash),
        ExecuteMsg::SetVerifiedBlock { root_hash, seq_no } => {
            set_verified_block(deps, &info.sender, root_hash, seq_no)
        }
    }
}

fn execute_update_owner(
    deps: DepsMut,
    info: MessageInfo,
    new_owner: Addr,
) -> Result<Response, ContractError> {
    OWNER.execute_update_admin::<Empty, Empty>(deps, info, Some(new_owner.clone()))?;

    Ok(Response::new().add_attributes(vec![
        ("action", "update_owner"),
        ("new_owner", new_owner.as_str()),
    ]))
}

pub fn parse_candidates_root_block(
    deps: DepsMut,
    boc: HexBinary,
) -> Result<Response, ContractError> {
    let mut validator = VALIDATOR.load(deps.storage)?;
    validator.parse_candidates_root_block(deps.storage, boc.as_slice())?;
    VALIDATOR.save(deps.storage, &validator)?;
    Ok(Response::new().add_attributes(vec![("action", "parse_candidates_root_block")]))
}

// this entrypoint is used mostly for testing or initialization
// where the admin knows the given validator set is already valid.
pub fn reset_validator_set(
    deps: DepsMut,
    sender: &Addr,
    boc: HexBinary,
) -> Result<Response, ContractError> {
    OWNER.assert_admin(deps.as_ref(), sender)?;
    let storage = deps.storage;
    let mut validator = VALIDATOR.load(storage)?;

    // update new candidates given the new block data
    validator.parse_candidates_root_block(storage, boc.as_slice())?;

    // skip verification and assume the new validator set is valid (only admin can call this)
    validator.init_validators(storage)?;

    // store the validator set in cache
    VALIDATOR.save(storage, &validator)?;
    Ok(Response::new().add_attributes(vec![("action", "reset_validator_set")]))
}

// should be called by relayers
pub fn verify_validators(
    deps: DepsMut,
    root_hash: HexBinary,
    file_hash: HexBinary,
    vdata: Vec<VdataHex>,
) -> Result<Response, ContractError> {
    let mut validator = VALIDATOR.load(deps.storage)?;
    let vdata_bytes = vdata
        .iter()
        .map(|data| {
            let node_id = to_bytes32(&data.node_id).unwrap();
            let r = to_bytes32(&data.r).unwrap();
            let s = to_bytes32(&data.s).unwrap();

            // transform from hex string to bytes32
            Vdata { node_id, r, s }
        })
        .collect::<Vec<Vdata>>();
    validator.verify_validators(
        deps.storage,
        deps.api,
        to_bytes32(&root_hash)?,
        to_bytes32(&file_hash)?,
        &vdata_bytes,
    )?;
    validator.set_validator_set(deps.storage, deps.api)?;
    VALIDATOR.save(deps.storage, &validator)?;
    Ok(Response::new().add_attributes(vec![("action", "verify_validators")]))
}

// should be called by relayers
pub fn verify_masterchain_block_by_validator_signatures(
    deps: DepsMut,
    block_header_proof: HexBinary,
    file_hash: HexBinary,
    vdata: Vec<VdataHex>,
) -> Result<Response, ContractError> {
    let validator = VALIDATOR.load(deps.storage)?;
    let vdata_bytes = vdata
        .iter()
        .map(|data| {
            let node_id = to_bytes32(&data.node_id).unwrap();
            let r = to_bytes32(&data.r).unwrap();
            let s = to_bytes32(&data.s).unwrap();

            // transform from hex string to bytes32
            Vdata { node_id, r, s }
        })
        .collect::<Vec<Vdata>>();
    let root_hash = validator.verify_masterchain_block_by_validator_signatures(
        deps.storage,
        deps.api,
        block_header_proof,
        to_bytes32(&file_hash)?,
        &vdata_bytes,
    )?;
    Ok(Response::new().add_attributes(vec![
        ("action", "verify_masterchain_block_by_validator_signatures"),
        ("root_hash", &root_hash.to_hex()),
    ]))
}

pub fn verify_shard_blocks(
    deps: DepsMut,
    shard_proof_links: Vec<HexBinary>,
    mc_block_root_hash: HexBinary,
) -> Result<Response, ContractError> {
    let validator = VALIDATOR.load(deps.storage)?;
    let attrs =
        validator.verify_shard_blocks(deps.storage, shard_proof_links, mc_block_root_hash)?;

    // validator.read_shard_state_unsplit(deps.storage, shard_state_boc.as_slice(), root_hash)?;
    Ok(Response::new()
        .add_attribute("action", "verify_shard_blocks")
        .add_attributes(attrs))
}

// this entrypoint is used mostly for testing or initialization
// where the admin knows the given block is surely verified.
pub fn set_verified_block(
    deps: DepsMut,
    caller: &Addr,
    root_hash: HexBinary,
    seq_no: u32,
) -> Result<Response, ContractError> {
    let validator = VALIDATOR.load(deps.storage)?;
    validator.set_verified_block(deps, caller, to_bytes32(&root_hash)?, seq_no)?;
    Ok(Response::new().add_attributes(vec![
        ("action", "set_verified_block"),
        ("root_hash", &root_hash.to_hex()),
    ]))
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn query(deps: Deps, _env: Env, msg: QueryMsg) -> StdResult<Binary> {
    match msg {
        QueryMsg::Config {} => to_json_binary(&get_config(deps)?),
        QueryMsg::GetCandidatesForValidators {
            start_after,
            limit,
            order,
        } => to_json_binary(&get_candidates_for_validators(
            deps,
            start_after,
            limit,
            order,
        )?),
        QueryMsg::GetValidators {
            start_after,
            limit,
            order,
        } => to_json_binary(&get_validators(deps, start_after, limit, order)?),
        QueryMsg::IsVerifiedBlock { root_hash } => to_json_binary(&is_verified_block(deps, root_hash)?),
        QueryMsg::IsSignedByValidator {
            validator_node_id,
            root_hash,
        } => to_json_binary(&is_signed_by_validator(deps, validator_node_id, root_hash)?),
        QueryMsg::NextValidatorUpdated {} => to_json_binary(&next_validator_updated(deps)?),
    }
}

pub fn get_config(deps: Deps) -> StdResult<ConfigResponse> {
    let owner = OWNER.query_admin(deps)?;
    Ok(ConfigResponse { owner: owner.admin })
}

pub fn get_candidates_for_validators(
    deps: Deps,
    start_after: Option<u64>,
    limit: Option<u32>,
    order: Option<u8>,
) -> StdResult<Vec<UserFriendlyValidator>> {
    let limit = limit.unwrap_or(DEFAULT_LIMIT).min(MAX_LIMIT) as usize;
    let mut allow_range =
        SIGNATURE_CANDIDATE_VALIDATOR.range_raw(deps.storage, None, None, map_order(order));
    if let Some(start_after) = start_after {
        let start = Some(Bound::exclusive::<u64>(start_after));
        allow_range =
            SIGNATURE_CANDIDATE_VALIDATOR.range_raw(deps.storage, start, None, map_order(order));
    }
    let candidates = allow_range
        .take(limit)
        .map(|item| item.map(|(_, mapping)| Validator::parse_user_friendly_validator(mapping)))
        .collect::<StdResult<Vec<UserFriendlyValidator>>>()?;
    Ok(candidates)
}

pub fn get_validators(
    deps: Deps,
    start_after: Option<String>,
    limit: Option<u32>,
    order: Option<u8>,
) -> StdResult<Vec<UserFriendlyValidator>> {
    let limit = limit.unwrap_or(DEFAULT_LIMIT).min(MAX_LIMIT) as usize;
    let range_start =
        start_after.map(|start| HexBinary::from_hex(&start).unwrap_or_default().to_vec());
    let start = calc_range_start(range_start).map(Bound::ExclusiveRaw);
    let allow_range = validator_set().range_raw(deps.storage, start, None, map_order(order));
    let validators = allow_range
        .take(limit)
        .map(|item| item.map(|(_, mapping)| Validator::parse_user_friendly_validator(mapping)))
        .collect::<StdResult<Vec<UserFriendlyValidator>>>()?;

    Ok(validators)
}

pub fn is_verified_block(deps: Deps, root_hash: HexBinary) -> StdResult<bool> {
    let validator = VALIDATOR.load(deps.storage)?;
    validator.is_verified_block(
        deps.storage,
        root_hash
            .as_slice()
            .try_into()
            .map_err(|err: TryFromSliceError| StdError::generic_err(err.to_string()))?,
    )
}

pub fn is_signed_by_validator(
    deps: Deps,
    validator_node_id: HexBinary,
    root_hash: HexBinary,
) -> StdResult<bool> {
    let validator = VALIDATOR.load(deps.storage)?;
    Ok(validator.is_signed_by_validator(
        deps.storage,
        to_bytes32(&validator_node_id)?,
        to_bytes32(&root_hash)?,
    ))
}

pub fn next_validator_updated(deps: Deps) -> StdResult<bool> {
    let validator = VALIDATOR.load(deps.storage)?;
    Ok(validator.next_validator_updated())
}

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn migrate(_deps: DepsMut, _env: Env, _msg: MigrateMsg) -> Result<Response, ContractError> {
    Ok(Response::default())
}

fn map_order(order: Option<u8>) -> Order {
    match order {
        Some(order) => {
            if order == 1 {
                Order::Ascending
            } else {
                Order::Descending
            }
        }
        None => Order::Ascending,
    }
}

// upper bound key by 1, for Order::Ascending
fn calc_range_start(start_after: Option<Vec<u8>>) -> Option<Vec<u8>> {
    start_after.map(|mut input| {
        // zero out all trailing 255, increment first that is not such
        for i in (0..input.len()).rev() {
            if input[i] == 255 {
                input[i] = 0;
            } else {
                input[i] += 1;
                break;
            }
        }
        input
    })
}
