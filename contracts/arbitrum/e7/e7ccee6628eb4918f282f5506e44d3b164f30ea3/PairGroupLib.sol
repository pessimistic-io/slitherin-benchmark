// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./DataType.sol";

library PairGroupLib {
    function validatePairGroupId(DataType.GlobalData storage _global, uint256 _pairGroupId) internal view {
        require(0 < _pairGroupId && _pairGroupId < _global.pairGroupsCount, "INVALID_PG");
    }
}

