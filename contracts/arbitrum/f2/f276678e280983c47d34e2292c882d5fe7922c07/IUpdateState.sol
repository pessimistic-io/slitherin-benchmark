// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./INameVersion.sol";
import "./IAdmin.sol";

interface IUpdateState is INameVersion, IAdmin {
    function resetFreezeStart() external;

    function balances(
        address account,
        address asset
    ) external view returns (int256);

    struct AccountPosition {
        int64 volume;
        int64 lastCumulativeFundingPerVolume;
        int128 entryCost;
    }

    function accountPositions(
        address account,
        bytes32 symbolId
    ) external view returns (AccountPosition memory);
}

