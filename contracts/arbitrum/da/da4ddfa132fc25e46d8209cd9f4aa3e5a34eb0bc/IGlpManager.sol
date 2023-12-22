// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import {IVault} from "./IVault.sol";

interface IGlpManager {
    function vault() external view returns (IVault);

    function usdg() external view returns (address);

    function MAX_COOLDOWN_DURATION() external view returns (uint256);

    function lastAddedAt(address _account) external returns (uint256);

    function getAums() external view returns (uint256[] memory);

    function cooldownDuration() external returns (uint256);
}

