// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "./IERC20.sol";
import { IFactorScale } from "./IFactorScale.sol";

interface IWrapperVault {
    function redeemRewards(address user) external returns (uint256[] memory);
}

contract MultipleClaimRewardsAdapter {
    error VaultNotActive();

    event ClaimRewards(address vault, address user, uint256[] results);

    address private immutable scale;

    constructor(address _scale) {
        scale = _scale;
    }

    function claimMultipleRewards(address[] calldata vaults, address user) external {
        for (uint i = 0; i < vaults.length; i++) {
            if (!IFactorScale(scale).isVaultActive(vaults[i])) revert VaultNotActive();
            uint256[] memory results = IWrapperVault(vaults[i]).redeemRewards(user);
            emit ClaimRewards(vaults[i], user, results);
        }
    }
}

