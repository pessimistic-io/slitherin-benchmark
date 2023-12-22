// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./IERC20Upgradeable.sol";
import "./IVotesUpgradeable.sol";

interface IL2ArbitrumToken is IERC20Upgradeable, IVotesUpgradeable {
    function mint(address recipient, uint256 amount) external;
}

