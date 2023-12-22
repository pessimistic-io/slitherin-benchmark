// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./ArbSys.sol";

/// @title Handles Arbitrum blockchain specific information.
abstract contract ArbitrumBlockchainInfo {
    function _getBlockNumber() internal view returns (uint256) {
        return ArbSys(address(100)).arbBlockNumber();
    }
}

