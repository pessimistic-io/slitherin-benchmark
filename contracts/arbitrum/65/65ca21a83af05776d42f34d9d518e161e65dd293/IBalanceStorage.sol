// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IdType.sol";


abstract contract IBalanceStorage {
    struct NFTCounter {
        uint32 mysteryCount;
        uint32 emptyCount;
        uint32[6] rarityIdToCount;

        IdType mysteryHead;
        IdType emptyHead;
        IdType[6] rarityIdToHead;
    }

    function _balances(address user) internal view virtual returns (NFTCounter storage);
}
