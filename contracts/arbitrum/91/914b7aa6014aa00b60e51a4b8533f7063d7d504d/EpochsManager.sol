// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IEpochsManager} from "./IEpochsManager.sol";

contract EpochsManager is IEpochsManager {
    /// @inheritdoc IEpochsManager
    function currentEpoch() external view returns (uint16) {
        return uint16((block.timestamp - startFirstEpochTimestamp()) / epochDuration());
    }

    /// @inheritdoc IEpochsManager
    function epochDuration() public view returns (uint256) {
        return 2592000; // NOTE: value taken from EpochsManager on Polygon (0xbA1067FB99Ad837F0e2895B57D1635Bdbefa789E)
    }

    /// @inheritdoc IEpochsManager
    function startFirstEpochTimestamp() public view returns (uint256) {
        return 1680595199; // NOTE: value taken from EpochsManager on Polygon (0xbA1067FB99Ad837F0e2895B57D1635Bdbefa789E)
    }
}

