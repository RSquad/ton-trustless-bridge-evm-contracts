use cosmwasm_std::{Decimal, QuerierWrapper, StdResult, Storage, Uint128};

use oraiswap::{
    asset::AssetInfo,
    router::{RouterController, SwapOperation},
};
use std::ops::Mul;
use tonbridge_bridge::{amount::Amount, msg::FeeData, state::Ratio};

use crate::state::TOKEN_FEE;

pub fn process_deduct_fee(
    storage: &dyn Storage,
    remote_token_denom: String,
    local_amount: Amount, // local amount
    relayer_fee: Uint128,
) -> StdResult<FeeData> {
    let local_denom = local_amount.denom();
    let (deducted_amount, token_fee) =
        deduct_token_fee(storage, remote_token_denom, local_amount.amount())?;

    let mut fee_data = FeeData {
        deducted_amount,
        token_fee: Amount::from_parts(local_denom.clone(), token_fee),
        relayer_fee: Amount::from_parts(local_denom.clone(), Uint128::zero()),
    };
    // if after token fee, the deducted amount is 0 then we deduct all to token fee
    if deducted_amount.is_zero() {
        fee_data.token_fee = local_amount;
        return Ok(fee_data);
    }

    fee_data.deducted_amount = deducted_amount.checked_sub(relayer_fee).unwrap_or_default();
    fee_data.relayer_fee = Amount::from_parts(local_denom.clone(), relayer_fee);
    // if the relayer fee makes the final amount 0, then we charge the remaining deducted amount as relayer fee
    if fee_data.deducted_amount.is_zero() {
        fee_data.relayer_fee = Amount::from_parts(local_denom.clone(), deducted_amount);
        return Ok(fee_data);
    }
    Ok(fee_data)
}

pub fn deduct_token_fee(
    storage: &dyn Storage,
    remote_token_denom: String,
    amount: Uint128,
) -> StdResult<(Uint128, Uint128)> {
    let token_fee = TOKEN_FEE.may_load(storage, &remote_token_denom)?;
    if let Some(token_fee) = token_fee {
        let fee = deduct_fee(token_fee, amount);
        let new_deducted_amount = amount.checked_sub(fee)?;
        return Ok((new_deducted_amount, fee));
    }
    Ok((amount, Uint128::from(0u64)))
}

pub fn deduct_fee(token_fee: Ratio, amount: Uint128) -> Uint128 {
    // ignore case where denominator is zero since we cannot divide with 0
    if token_fee.denominator == 0 {
        return Uint128::from(0u64);
    }

    amount.mul(Decimal::from_ratio(
        token_fee.nominator,
        token_fee.denominator,
    ))
}

pub fn get_swap_token_amount_out(
    querier: &QuerierWrapper,
    offer_amount: Uint128,
    swap_router_contract: &RouterController,
    ask_asset_info: AssetInfo,
    relayer_fee_token: AssetInfo,
) -> Uint128 {
    if ask_asset_info.eq(&relayer_fee_token) {
        return offer_amount;
    }

    let orai_asset = AssetInfo::NativeToken {
        denom: "orai".to_string(),
    };

    let swap_ops = if ask_asset_info.eq(&orai_asset) || relayer_fee_token.eq(&orai_asset) {
        vec![SwapOperation::OraiSwap {
            offer_asset_info: relayer_fee_token,
            ask_asset_info,
        }]
    } else {
        vec![
            SwapOperation::OraiSwap {
                offer_asset_info: relayer_fee_token,
                ask_asset_info: orai_asset.clone(),
            },
            SwapOperation::OraiSwap {
                offer_asset_info: orai_asset,
                ask_asset_info,
            },
        ]
    };

    swap_router_contract
        .simulate_swap(querier, offer_amount, swap_ops)
        .map(|data| data.amount)
        .unwrap_or_default()
}
