# Описание контрактов
## 1. BitReader

Контракт содержит вспомогательные методы для чтения информации из boc'а.
Большинство методов контракта увеличивают поле cursor структуры СellData (побочный эффект метода).

### Методы

**1.1 readBit(data, cells, cellIdx)**

Возвращает считанный бит в виде uint8.

**1.2 readBool(data, cells, cellIdx)**

Возвращает считанный бит в виде bool значения.

**1.3 readUint, readUint64, readUint32, readUint8 (data, cells, cellIdx, size)**

Возвращает size считанных битов в uint8, uint16, uint32, uint64, uint соответственно.

**1.4 readBytes32BitSize(data, cells, cellIdx, size)**

Возвращает size считанных битов в виде bytes32.

**1.5 readBytes32ByteSize(data, cells, cellIdx, sizeb)**

возвращает sizeb считанных байтов в виде bytes32.

**1.6 readCell(cells, cellIdx)**

Возвращает первый необработанный парсингом ref cell’а (в виде индекса).

**1.7 readUnaryLength(data, cells, cellIdx)**

Возвращает количество последовательно идущих единиц.

**1.8 log2Ceil(x)**

Логарифм с округлением вверх.

**1.8 parseDict(data, cells, cellIdx, keySize) и doParse(data, prefix, cells, cellIdx, n, cellIdxs)**

Возвращают релизацию Hashmap, в данном случае — массив индексов cell’ов (cellIdx). Ограничения
Метод обрабатывает до 32 элементов включительно.

## 2. TreeOfCellsParser

Контракт для работы с tree of cells. Основными методами являются parseSerializedHeader - для получения информации о содержимом boc'а и get_tree_of_cells - для получения tree of cells (ToC) в ввиде массива для дальнейшего использования.

### Методы

**2.1 readInt(data, size)**

Возвращает uint256 значение, считанное из boc'а.

**2.2 parseSerializedHeader(boc)**

Возвращает информацию о содержимом boc. Метод может считать информацию с любого из трех вариантов boc.

**Ограничения:**

- Метод работает с BOC которые содержат один и только один root cell.

**2.3 get_tree_of_cells(boc, info)**

Возвращает tree of cells, соответствующее поданному boc.

**Ограничения:**

- Не может обработать boc в котором уже указаны индексы cell.
- Так как за основу взята c++ реализация, так же как и оригинал, не может работать с absent cells. Максимум cells для обрабатываемого boc — 100.

**2.4 get_indexes(boc, info)**

Возвращает массив индексов cells. При наличии индексов в boc возвращает ошибку.

**2.5 init_cell_serialization_info(data, ref_byte_size)**

Возвращает информацию о cell.

**Ограничения:**
- Не работает с absent cells

**2.6 count_setbits(n)**

вспомогательный метод, используется вместо c++ реализации get_hashes_count()

**2.7 deserialize_cell(idx, cell_slice, custom_indexes, ref_byte_size, cell_count)**

Возвращает cell.

**2.8 get_cell_slice(idx, cells_slice, custom_indexes)**

Возвращает байты cell для дальнейшей обработки.

**2.9 create_data_cell(cell_slice, refs, cell_info)**

Вспомогательный метод для 2.7 deserialize_cell, добавляет в cell refs, флаг special и сбрасывает поле cursor.

**2.10 calcHashesForToc(boc, info, cells)**

Рассчитывает хэши для всех cell'ов данного ToC.

**2.11 getHashesCount(mask), getHashesCountFromMask(mask)**

Возвращает количество хэшей на основе данного поля mask из cell'а.

**2.12 getLevel(mask) getLevelFromMask(mask)**

Возвращает максимальный level хэшей для данного поля mask из cell'а.

**2.12 isLevelSignificant(level, mask)**

Возвращает true, если данный уровень хэша важен для подсчета хэшей других cell'ов.

**2.13 getDepth(data, level, cells, cellIdx)**

Возвращает depth\[hash_i\].

**2.14 applyLevelMask(level, levelMask)**

Возвращает наложение levelMask на level. (levelMask & ((1 << level) - 1)).

**2.15 calcHashForRefs(data, cell_info, cells, i, cell_slice)**

Рассчитывает хэш текущего cell (с учетом уже посчитанных хэшей его ref'ок).

**2.16 getHash(data, level, cells, cellIdx)**

Возвращает хэш cell'а соответствующий поданному level'у.

## 3. TransactionParser

Контракт для чтения данных транзакции и поиска нужного нам сообщения.

### Методы

**3.1 parseTransactionHeader(data, cells, rootIdx)**

Возвращает структуру с основной информацией о транзакции.

**3.2 parseCurrencyCollection(data, cells, cellIdx)**

Возвращает информацию о том, сколько и каких монет было использовано в транзакции в виде bytes32. 

**Ограничения:**

- Не возвращает custom currencies, только тоны.

**3.3 readCoins(data, cells, cellIdx)**

Возвращает количество тонов для какого либо поля.
  
**3.4 parseMessagesHeader(data, cells, messagesIdx)**

Возвращает messageHeader , содержащий в себе входящие и исходящие сообщения.

**3.5 parseMessage(data, cells, messageIdx)**

Возвращает результат парсинга Message.

**3.6 getDataFromMessages(bocData, cells, outMessages)**

Возвращает eht_address и amount из нужного нам сообщения.

**3.7 parseCommonMsgInfo(data, cells, messagesIdx)**

Возвращает тип сообщения (internal, outgoing external, Incoming external) и общую информацию о сообщении.

**3.8 readAddress(data, cells, messagesIdx)**

Считывает и возвращает адрес из тон-блокчейна.

**Ограничения:**

- Не реализована обработка адреса типа 3:
```
addr_var$11 anycast:(Maybe Anycast) addr_len:(## 9)
 workchain_id:int32 address:(bits addr_len) = MsgAddressInt;
```

## 4. BlockParser

Контракт для чтения данных блока, содержит в себе методы для проверки нахождения транзакции в блоке, а так же методы парсинга и обновления списка валидаторов.

### Методы

**4.1 verifyValidators(file_hash, vdata\[20\])**

Проверяет подписи валидаторов для конкретной сигнатуры (сoncat(signature_prefix, root_hash, file_hash)). Для каждого валидатора, если подпись верна, обновляется поле verified, в которое записывается root_hash, для которого была проверка.
Используется алгоритм из контракта(библиотеки) Ed25519.

**Ограничения:**

- vdata строго ограничен 20'ю элементами и в текущей реализации все элементы должны быть валидными, т.е. если пользователю необходимо проверить < 20 подписей, ему нужно дополнить массив дубликатами.

**4.2 setValidatorSet()**

Сохраняет новый список валидаторов в поле validatorSet из поля candidatesForValidatorSet и очищает последний если выполнено одно из двух условий:

1) validatorSet пуст и метод вызвал овнер контракта (инициилизация)
2) вес проголосовавших за обновление валидаторов составляет > 2/3 общего веса validatorSet

Во втором случае "проголосовавшим" считается валидатор, у которого поле verified == текущему значению поля root_hash в контракте.

**4.3 computeNodeId(publicKey)**

Возвращает node_id валидатора

**4.4 readValidatorDescription(data, cellIdx, cell)**

Возвращает информацию о валидаторе

**4.5 parseDict2(data, cells, cellIdx, keySize) и  doParse2(data, prefix, cells, cellIdx, n, cellIdxs)**

Сохраняют хэши и оставшиаеся длины префиксов для pruned ячеек. Так как полный boc с валидаторами мы не можем прочесть за 1 раз, данные методы используются чтобы запомнить, какие части хэшмапа с валидаторами нам надо будет прочитать в дальнейшем.

**4.6 parseCandidatesRootBlock(boc, rootIdx, treeOfCells)**

Метод для чтения boc'а keyblock'а с спруненным списком валидаторов.
parseBlockExtra2, parseMcBlockExtra2, parseConfigParams2, parseConfigParam342 так же используются для чтения этого блока, чтобы добраться до configParams34 и, с помощью parseDict2 запомнить список спруненных ячеек, ToC'и которых нам подадут в дальнейшем.

**4.7 parsePartValidators(data, cellIdx, cells)**

Метод для чтения поддерева configParam34, сохраняет найденных валидаторов.
Если подать поддерево НЕ из текущего keyblock'а, выдаст ошибку.
Если поддеревья закончились, вызовет setValidators().

**4.8 parse_block(proofBoc, proofBocInfo, proofTreeOfCells, txRootHash, transaction) и parse_block_extra(proofBoc, cells, cellIdx, txRootHash, transaction)**

Методы проверки нахождения хэша транзакции в блоке. Проверяет как наличие хэша среди хэшей cell'ов спруненного блока, так и его местоположение в дереве.

readUintLeq, check_block_info

**4.9 check_block_info(proofBoc, cells, cellIdx, transaction) и readUintLeq(proofBoc, cells, cellIdx, n)**

Методы для корректного чтения start_lt и end_lt блока, а так же проверки того, что lt транзакции находится в промежутке времени работы блока (transaction.lt >= start_lt || transaction.lt <= end_lt).

## Примечания по контрактам

В документации не указаны методы следующих контрактов:
- BocHeaderAdapter - предыдущая реализация, сейчас используется для справки по неоторым методам и так же содержит обобщенные методы для чтения сообщения из транзакции; для проверки транзакции. Будет удален.
- TocHashes - контракт с методами для рассчета хэшей ячеек ToC'а, все методы которого есть в TreeOfCellsParser
- Ed25519 и Sha512 - содержат соответствующий алгоритм Ed25519.

# Алгоритмы взаимодействия (data flow)

Логику работы контрактов bridge можно описать следующим образом:

1) Initial state - после деплоя контрактов админ (овнер контрактов) инициилизирует начальный список валидаторов.
2) После первого шага в контракт подаются новые key block'и и, если в них изменился список валидаторов, производится алгоритм обновления списка валидаторов.
3) **Todo** Так же в контракт подаются и обычные блоки для проверки того, находятся ли они в блокчейне, если да, то контракт сохраняет root_hash этого блока с отметкой того, что он валиден.
4) При подаче в контракт транзакции, мы получаем данные из сообщения этой транзакции (с eth_address и amount) и проверяем, валидна ли транзакций. Транзакция является валидной, если:
- hash ToC'а транзакции (transaction_hash) содержится в ToC'е некоторого блока
- root_hash блока находится в списке проверенных блоков контракта (т.е. блок находится в блокчейне)

## 1. Чтение сообщения из транзакции и валидация транзакции

- Получаем ToC из boc'а транзакции
```
bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
```

- достаем данные из сообщения транзакции
```
transaction = parseTransactionHeader(cells, rootIdx);
messages = parseMessagesHeader(
            cells,
            readCell(cells, rootIdx)
        );
msgData = getDataFromMessages(cells, messages.outMessages);
```
- Проверяем нахождение транзакции в блоке (считываем ToC запруненного блока и вызываем проверку)
```
blockBocHeader = await treeOfCellsParser.parseSerializedHeader(blockBoc);
blockToc = await treeOfCellsParser.get_tree_of_cells(blockBoc, blockBocHeader);
isValid = parse_block(blockBoc,
                blockBocHeader,
                blockToc,
                toc\[bocHeader.rootIdx\]._hash\[0\],
                transaction);
```

В msgData хранится eth_address и amount, isValid - находится ли транзакция в блоке.

## 2. Работа со списком валидаторов и key block
### 2.1 Инициилизация списка валидаторов

**2.1.1. Чтение информации о списке валидаторов из спруненного ключевого блока.**

Контракт запоминает root_hash, хэши поддеревьев хэшмапа валидаторов.
```
bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);

// load block with prunned validators
await blockParser.parseCandidatesRootBlock(boc, bocHeader.rootIdx, toc);
```
**2.1.2 Чтение списка валидаторов из частей хэшмапа configParams34.**

Части configParams34 подаются в соответсвии с частичным порядком, который определен в изначальном ToC, дважды считать одну и ту же часть не выйдет по require. При чтении последней части внутри контракта автоматически вызовется setValidatorSet().
Контракт автоматически при добавлении валидатора обновляет так же и общий вес сохраненных валидаторов. Хранится лишь топ 100 по весу валидаторов.
```
// load validators
boc = initialBocLeaf0;
bocHeader = await treeOfCellsParser.parseSerializedHeader(boc);
toc = await treeOfCellsParser.get_tree_of_cells(boc, bocHeader);
await blockParser.parsePartValidators(boc, bocHeader.rootIdx, toc);
```

### 2.2 Обновление списка валидаторов

**2.2.1 Проверка подписей валидаторов в новом ключевом блоке**

Проверяем по 20 подписей валидаторов.
```
verifyValidators(fileHash, {node_id, r, s}[20]);
```
**2.2.2 Чтение и сохранение нового списка валидаторов**

Алгоритм тот же, что и в 2.1
