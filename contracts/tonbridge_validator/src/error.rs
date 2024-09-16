use std::{array::TryFromSliceError, num::ParseIntError};

use cosmwasm_std::StdError;
use cw_controllers::AdminError;
use thiserror::Error;
use tonlib::cell::TonCellError;

#[derive(Error, Debug)]
pub enum ContractError {
    #[error("{0}")]
    Std(#[from] StdError),

    #[error("{0}")]
    TonCellError(#[from] TonCellError),

    #[error("{0}")]
    AdminError(#[from] AdminError),

    #[error("{0}")]
    ParseIntError(#[from] ParseIntError),

    #[error("{0}")]
    TryFromSliceError(#[from] TryFromSliceError),

    #[error("Unauthorized")]
    Unauthorized {},
}

impl From<ContractError> for StdError {
    fn from(source: ContractError) -> Self {
        Self::generic_err(source.to_string())
    }
}
