export function printToC(toc: any, boc: any) {
  console.log(
    toc
      .filter((cell: any) => cell.cursor.gt(0))
      .map((cell: any, id: any, a: any) => ({
        id,
        special: cell.special,
        cursor: cell.cursor.toNumber(),
        refs: cell.refs
          .filter((ref: any) => !ref.eq(255))
          .map((ref: any) => ref.toNumber()),
        data: boc
          .toString("hex")
          // .slice(bocHeader.data_offset.toNumber())
          .slice(
            Math.floor(cell.cursor.div(4).toNumber()),
            // Math.floor(cell.cursor.div(8).toNumber()) +
            id === 0 ? 128 : Math.floor(a[id - 1].cursor.toNumber() / 4)
          ),
        bytesStart: cell.cursor.toNumber() % 8,
        hash: cell._hash,
        depth: cell.depth,
        level_mask: cell.level_mask,
        // distance:
        //   id === 0
        //     ? 128
        //     : Math.floor(a[id - 1].cursor.toNumber() / 8) -
        //       Math.floor(cell.cursor.div(8).toNumber()),
      }))
  );
}
