use cosmwasm_schema::cw_serde;
use cosmwasm_std::CanonicalAddr;
use tonlib::cell::{Cell, CellParser, TonCellError};

use crate::types::{AckPacket, BridgePacketDataRaw, Status};

pub trait ITransactionParser {
    fn parse_packet_data(&self, cell: &Cell) -> Result<BridgePacketDataRaw, TonCellError>;
    fn parse_ack_data(&self, cell: &Cell) -> Result<AckPacket, TonCellError>;
    fn load_address(parser: &mut CellParser) -> Result<Option<CanonicalAddr>, TonCellError>;
}

pub const RECEIVE_PACKET_MAGIC_NUMBER: u32 = 0xa64c12a3; // crc32("op::send_to_cosmos")
pub const SEND_TO_TON_MAGIC_NUMBER: u32 = 0xae89be5b; // crc32("op::send_to_ton")

#[cw_serde]
#[derive(Default)]
pub struct TransactionParser {}

impl ITransactionParser for TransactionParser {
    fn load_address(parser: &mut CellParser) -> Result<Option<CanonicalAddr>, TonCellError> {
        let num_bytes = parser.load_u8(8)?;
        if num_bytes == 0 {
            Ok(None)
        } else {
            Ok(Some(CanonicalAddr::from(
                parser.load_bytes(num_bytes as usize)?,
            )))
        }
    }

    fn parse_packet_data(&self, cell: &Cell) -> Result<BridgePacketDataRaw, TonCellError> {
        let mut parser = cell.parser();

        let magic_number = parser.load_u32(32)?;
        if magic_number != RECEIVE_PACKET_MAGIC_NUMBER {
            return Err(TonCellError::cell_parser_error(
                "Not a receive packet from TON to CW",
            ));
        }
        let packet_seq = parser.load_u64(64)?;
        let token_origin = parser.load_u32(32)?;
        let amount = parser.load_u128(128)?;
        let timeout_timestamp = parser.load_u64(64)?;
        let receiver = TransactionParser::load_address(&mut parser)?;
        if receiver.is_none() {
            return Err(TonCellError::cell_parser_error(
                "receiver not contain in packet data",
            ));
        }

        let source_denom = parser.load_address()?;

        if cell.references.is_empty() {
            return Err(TonCellError::cell_parser_error(
                "Packet data does not have 1 references to parse packet data",
            ));
        }

        let src_sender = cell.references[0].parser().load_address()?;

        let memo = if cell.references.len() > 1 {
            Some(cell.references[1].as_ref().clone())
        } else {
            None
        };

        Ok(BridgePacketDataRaw {
            seq: packet_seq,
            token_origin,
            timeout_timestamp,
            src_denom: source_denom,
            src_sender,
            amount,
            receiver: receiver.unwrap(),
            memo,
        })
    }

    fn parse_ack_data(&self, cell: &Cell) -> Result<AckPacket, TonCellError> {
        let mut parser = cell.parser();
        let magic_number = parser.load_u32(32)?;
        if magic_number != SEND_TO_TON_MAGIC_NUMBER {
            return Err(TonCellError::cell_parser_error("Not a ack"));
        }
        let packet_seq = parser.load_u64(64)?;
        let status = Status::from_value(parser.load_u8(2)?);
        if status.is_none() {
            return Err(TonCellError::cell_parser_error("Missing status in ack"));
        }

        Ok(AckPacket {
            seq: packet_seq,
            status: status.unwrap(),
        })
    }
}

#[cfg(test)]
mod tests {

    use std::str::FromStr;

    use cosmwasm_std::{CanonicalAddr, HexBinary, Uint128};
    use tonlib::{
        address::TonAddress,
        cell::{BagOfCells, Cell, CellBuilder, TonCellError},
        responses::MessageType,
    };

    use crate::{
        transaction_parser::SEND_TO_TON_MAGIC_NUMBER,
        types::{AckPacket, BridgePacketData, Status},
    };

    use super::{ITransactionParser, TransactionParser, RECEIVE_PACKET_MAGIC_NUMBER};

    #[test]
    fn test_load_address() {
        //case 1: None address
        let mut cell_builder = CellBuilder::new();
        cell_builder.store_u8(8, 0).unwrap();
        let res =
            TransactionParser::load_address(&mut cell_builder.build().unwrap().parser()).unwrap();
        assert_eq!(res, None);

        // case 2: Happy case
        let address: Vec<u8> = vec![
            23, 12, 3, 5, 13, 30, 10, 3, 20, 28, 27, 5, 31, 12, 11, 15, 3, 1, 22, 13, 21, 3, 30,
            20, 12, 3, 16, 0, 11, 14, 26, 4,
        ];
        let mut cell_builder = CellBuilder::new();
        cell_builder.store_u8(8, address.len() as u8).unwrap();
        cell_builder.store_slice(address.as_slice()).unwrap();
        let res =
            TransactionParser::load_address(&mut cell_builder.build().unwrap().parser()).unwrap();
        assert_eq!(res.unwrap(), CanonicalAddr::from(address))
    }

    #[test]
    fn test_parse_packet_data() {
        let seq = 1u64;
        let token_origin = 2u32;
        let amount = 3u128;
        let timeout_timestamp = 4u64;

        let mut cell_builder = CellBuilder::new();
        let tx_parser = TransactionParser::default();
        let address: Vec<u8> = vec![
            23, 12, 3, 5, 13, 30, 10, 3, 20, 28, 27, 5, 31, 12, 11, 15, 3, 1, 22, 13, 21, 3, 30,
            20, 12, 3, 16, 0, 11, 14, 26, 4,
        ];

        // case 1: invalid no-op -> invalid packet
        cell_builder
            .store_slice(&SEND_TO_TON_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        let err = tx_parser
            .parse_packet_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(
            err,
            TonCellError::cell_parser_error("Not a receive packet from TON to CW")
        );

        // case 2: missing receiver

        let mut cell_builder = CellBuilder::new();
        cell_builder
            .store_slice(&RECEIVE_PACKET_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        cell_builder.store_slice(&seq.to_be_bytes()).unwrap(); // seq
        cell_builder
            .store_slice(&token_origin.to_be_bytes())
            .unwrap(); // token origin
        cell_builder.store_slice(&amount.to_be_bytes()).unwrap(); // amount
        cell_builder
            .store_slice(&timeout_timestamp.to_be_bytes())
            .unwrap(); // timeout

        cell_builder.store_u8(8, 0u8).unwrap();
        let err = tx_parser
            .parse_packet_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(
            err,
            TonCellError::cell_parser_error("receiver not contain in packet data")
        );

        // case3: missing ref
        let mut cell_builder = CellBuilder::new();
        cell_builder
            .store_slice(&RECEIVE_PACKET_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        cell_builder.store_slice(&seq.to_be_bytes()).unwrap(); // seq
        cell_builder
            .store_slice(&token_origin.to_be_bytes())
            .unwrap(); // token origin
        cell_builder.store_slice(&amount.to_be_bytes()).unwrap(); // amount
        cell_builder
            .store_slice(&timeout_timestamp.to_be_bytes())
            .unwrap(); // timeout

        cell_builder.store_u8(8, address.len() as u8).unwrap(); //store receiver bytes len
        cell_builder.store_slice(address.as_slice()).unwrap(); //store receiver
        cell_builder
            .store_address(
                &TonAddress::from_str("EQAeNPObD65owWYLyQlPdnD8qKU9SmOKOrC3q567gbjm68Or").unwrap(),
            )
            .unwrap(); // denom

        let err = tx_parser
            .parse_packet_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(
            err,
            TonCellError::cell_parser_error(
                "Packet data does not have 1 references to parse packet data"
            )
        );

        // case 4: Happy case
        cell_builder
            .store_reference(
                &CellBuilder::new()
                    .store_address(
                        &TonAddress::from_str("EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh")
                            .unwrap(),
                    )
                    .unwrap()
                    .build()
                    .unwrap()
                    .to_arc(),
            )
            .unwrap();
        let res = tx_parser
            .parse_packet_data(&cell_builder.build().unwrap())
            .unwrap()
            .to_pretty()
            .unwrap();
        assert_eq!(
            res,
            BridgePacketData {
                seq,
                token_origin,
                timeout_timestamp,
                src_sender: "EQCkkxPb0X4DAMBrOi8Tyf0wdqqVtTR9ekbDqB9ijP391nQh".to_string(),
                src_denom: "EQAeNPObD65owWYLyQlPdnD8qKU9SmOKOrC3q567gbjm68Or".to_string(),
                amount: Uint128::from(amount),
                receiver: CanonicalAddr::from(address),
                memo: None
            }
        );
    }

    #[test]
    fn test_parse_ack_packet() {
        let seq = 1u64;
        let mut cell_builder = CellBuilder::new();
        let tx_parser = TransactionParser::default();

        // case 1: invalid no-op -> invalid packet
        cell_builder
            .store_slice(&RECEIVE_PACKET_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        let err = tx_parser
            .parse_ack_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(err, TonCellError::cell_parser_error("Not a ack"));

        // case 2: missing data => invalid packet
        let mut cell_builder = CellBuilder::new();
        cell_builder
            .store_slice(&SEND_TO_TON_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        let err = tx_parser
            .parse_ack_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(
            err,
            TonCellError::cell_parser_error("failed to fill whole buffer")
        );

        // case 3: wrong status => invalid packet
        cell_builder.store_slice(&seq.to_be_bytes()).unwrap();
        cell_builder.store_u8(2, 3).unwrap();
        let err = tx_parser
            .parse_ack_data(&cell_builder.build().unwrap())
            .unwrap_err();
        assert_eq!(
            err,
            TonCellError::cell_parser_error("Missing status in ack")
        );

        // case 4: happy case
        let mut cell_builder = CellBuilder::new();
        cell_builder
            .store_slice(&SEND_TO_TON_MAGIC_NUMBER.to_be_bytes())
            .unwrap();
        cell_builder.store_slice(&seq.to_be_bytes()).unwrap();
        cell_builder.store_u8(2, 0).unwrap();

        let res = tx_parser
            .parse_ack_data(&cell_builder.build().unwrap())
            .unwrap();
        assert_eq!(
            res,
            AckPacket {
                seq,
                status: crate::types::Status::Success
            }
        )
    }

    #[test]
    fn test_parse_ack_from_boc() {
        let tx_boc = "b5ee9c72010211010003010003b572b5a568181d18297026b02442340fffccf120afdb7606c7fbaa9d9787f92447e00002b627c86d301af74e8e646a00f4eccfba31ec041dda7acb120387acc35d2d9ab974365e6e11b00002b627bb133816690e235000546cb632a80102030201e004050082726082e6b7a2eab9963ddaf62b296efce33786b7188720641ac73fe4248ea28a369843a0f96fb541a341e88ac232698045c753be605710590ead2d845cbd89710002170450890cc053f8186b8b14110f1001b16801dbca20284058a8f0ed1b13985948fe50d91fff9eebe8a0f9757dfae30d316e03000ad695a0607460a5c09ac09108d03fff33c482bf6dd81b1feeaa765e1fe4911f90cc053f8006148420000056c4f8939404cd21c448c0060201dd0a0b01181ae4fbbb0000000000000000070143c0053b7fd39b412240b430f87c07fa998947b7553eee39e15b0f0735b3d7147f68e8080193ae89be5b00000000000000071f886e350000000000000000000000003b9aca00000000006690efc28002dca7653b4c646d7d66400ffc787b1f6d70e8a404e3438ee55e6376927dfb19c409002a14d931bb907b6e9bc806af38d7240bf6f7a2765d680101200c0101200d00b1680056b4ad0303a3052e04d604884681fff99e2415fb6ec0d8ff7553b2f0ff2488fd0005b94eca7698c8dafacc801ff8f0f63edae1d14809c6871dcabcc6ed24fbf63390ee6b28000608235a000056c4f90da604cd21c46a40019fe0015ad2b40c0e8c14b8135812211a07ffe6789057edbb0363fdd54ecbc3fc9223f300da7a8d19481a973dd6fb67eb4380a528928cf6a18a2858862631e7293f59806600002b627c86d3036690e235600e0019ae89be5b000000000000000720009e47634c3d09000000000000000000f700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006fc986b5304c2562cc000000000004000000000005f87991754949694039a4accb1ddc186027164e56db2ef679fcae10c4e252b0e640d02cec";
        let tx_cells = BagOfCells::parse(&HexBinary::from_hex(tx_boc).unwrap()).unwrap();
        let tx_root = tx_cells.single_root().unwrap();
        let transaction = Cell::load_transaction(tx_root, &mut 0, &mut tx_root.parser()).unwrap();
        let tx_parser = TransactionParser::default();

        for out_msg in transaction.out_msgs.into_values() {
            if out_msg.data.is_none() {
                continue;
            }
            let out_msg = out_msg.data.unwrap();
            if out_msg.info.msg_type != MessageType::ExternalOut as u8 {
                continue;
            }

            let cell = out_msg.body.cell_ref.unwrap().0.unwrap().cell;
            let packet_data = tx_parser.parse_ack_data(&cell).unwrap();
            assert_eq!(
                packet_data,
                AckPacket {
                    seq: 7,
                    status: Status::Success
                }
            )
        }
    }
}
