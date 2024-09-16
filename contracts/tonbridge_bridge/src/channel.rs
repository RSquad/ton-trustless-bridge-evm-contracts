use cosmwasm_std::{StdError, StdResult, Storage, Uint128};

use crate::state::REMOTE_INITIATED_CHANNEL_STATE;

pub fn increase_channel_balance(
    storage: &mut dyn Storage,
    denom: &str, // should be ibc denom
    amount: Uint128,
) -> StdResult<()> {
    let store = REMOTE_INITIATED_CHANNEL_STATE.key(denom);
    // whatever error or not found, return default
    let mut state = store.load(storage).unwrap_or_default();
    state.outstanding += amount;
    state.total_sent += amount;

    store.save(storage, &state)
}

pub fn decrease_channel_balance(
    storage: &mut dyn Storage,
    denom: &str, // should be ibc denom
    amount: Uint128,
) -> StdResult<()> {
    let store = REMOTE_INITIATED_CHANNEL_STATE.key(denom);
    let Ok(mut state) = store.load(storage) else {
        return Err(StdError::generic_err("Channel does not exist"));
    };

    state.outstanding = state.outstanding.checked_sub(amount)?;
    store.save(storage, &state)
}
