use cosmwasm_schema::cw_serde;
use cosmwasm_std::{Addr, HexBinary, QuerierWrapper, StdError, Storage};

use tonbridge_parser::to_bytes32;
use tonbridge_validator::wrapper::ValidatorWrapper;
use tonlib::{
    cell::{BagOfCells, Cell},
    responses::{MaybeRefData, MessageType, Transaction, TransactionMessage},
};

use crate::{error::ContractError, state::PROCESSED_TXS};

#[cw_serde]
pub struct Bridge {
    pub validator: ValidatorWrapper,
}

impl Bridge {
    pub fn new(validator_contract_addr: Addr) -> Self {
        Self {
            validator: ValidatorWrapper(validator_contract_addr),
        }
    }
}

impl Bridge {
    pub fn validate_transaction_out_msg(
        out_msg: MaybeRefData<TransactionMessage>,
        bridge_adapter_addr: String,
    ) -> Option<Cell> {
        if out_msg.data.is_none() {
            return None;
        }
        let out_msg = out_msg.data.unwrap();
        if out_msg.info.msg_type != MessageType::ExternalOut as u8 {
            return None;
        }
        // verify source of tx is bridge adapter contract
        if out_msg.info.src.to_string() != bridge_adapter_addr {
            return None;
        }

        if out_msg.body.cell_ref.is_none() {
            return None;
        }
        let cell = out_msg.body.cell_ref.unwrap().0;
        if cell.is_none() {
            return None;
        }

        // body cell
        Some(cell.unwrap().cell)
    }

    pub fn read_transaction(
        &self,
        storage: &mut dyn Storage,
        querier: &QuerierWrapper,
        tx_proof: &[u8],
        tx_boc: &[u8],
    ) -> Result<Transaction, ContractError> {
        let tx_cells = BagOfCells::parse(tx_boc)?;
        let tx_root = tx_cells.single_root()?;
        let transaction = Cell::load_transaction(tx_root, &mut 0, &mut tx_root.parser())?;
        let transaction_hash = to_bytes32(&HexBinary::from(transaction.hash.clone()))?;

        let tx_proof_cells = BagOfCells::parse(tx_proof)?;
        let tx_proof_cell_first_ref = tx_proof_cells.single_root()?.reference(0)?;
        let root_hash = tx_proof_cell_first_ref.get_hash(0);

        let is_root_hash_verified = self
            .validator
            .is_verified_block(querier, HexBinary::from(root_hash))?;

        if !is_root_hash_verified {
            return Err(ContractError::Std(StdError::generic_err(
                "The block root hash of the tx proof is not verified or invalid. Cannot bridge!",
            )));
        }

        let block_extra_cell = tx_proof_cell_first_ref.reference(3)?;
        let block_extra =
            Cell::load_block_extra(block_extra_cell, &mut 0, &mut block_extra_cell.parser())?;
        if block_extra.account_blocks.is_none() {
            return Err(ContractError::Std(StdError::generic_err(
                "Account blocks are empty. This tx proof is broken",
            )));
        }
        let account_blocks = block_extra.account_blocks.unwrap();
        let mut found_matched_tx = false;
        for acc_block in account_blocks.into_iter() {
            let txs = acc_block.1.transactions;
            for (_key, tx) in txs {
                if let Some(tx_cell) = tx.cell {
                    let tx_hash = tx_cell.get_hash(0);
                    if tx_hash.eq(&transaction_hash) {
                        found_matched_tx = true;
                        break;
                    }
                }
            }
            if found_matched_tx {
                break;
            }
        }

        if !found_matched_tx {
            return Err(ContractError::Std(StdError::generic_err(
                "The tx hash is not in the tx proof's tx hashes!",
            )));
        }

        let is_tx_processed = PROCESSED_TXS
            .may_load(storage, &transaction_hash)?
            .unwrap_or(false);

        if is_tx_processed {
            return Err(ContractError::Std(StdError::generic_err(
                "This tx has already been processed",
            )));
        }

        PROCESSED_TXS.save(storage, &transaction_hash, &true)?;
        Ok(transaction)
    }
}
