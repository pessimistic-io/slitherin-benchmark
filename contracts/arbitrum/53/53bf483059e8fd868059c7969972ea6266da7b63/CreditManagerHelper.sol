// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { ICreditManager as IOriginCreditManager } from "./ICreditManager.sol";
import { IAbstractVault } from "./IAbstractVault.sol";
import { IShareLocker as IOriginShareLocker } from "./IShareLocker.sol";

import "./console.sol";

interface ICreditManager is IOriginCreditManager {
    function pendingRewards(address _recipient) external view returns (uint256);

    function accRewardPerShare() external view returns (uint256);

    function totalShares() external view returns (uint256);

    function users(address _recipient) external view returns (uint256, uint256, uint256);
}

interface IShareLocker is IOriginShareLocker {
    function pendingRewards() external view returns (uint256);
}

/* 
This contract is used to calculate the unclaimed earnings of CreditManager.
*/

contract CreditManagerHelper {
    uint256 private constant PRECISION = 1e18;

    function pendingRewards(address _creditManager, address _recipient) public view returns (uint256) {
        address vault = ICreditManager(_creditManager).vault();
        address shareLocker = IAbstractVault(vault).creditManagersShareLocker(_creditManager);
        uint256 unclaimed = IShareLocker(shareLocker).pendingRewards();

        uint256 rewards;
        uint256 shares;
        uint256 rewardPerSharePaid;

        uint256 accRewardPerShare = ICreditManager(_creditManager).accRewardPerShare();
        uint256 totalShares = ICreditManager(_creditManager).totalShares();

        (shares, rewards, rewardPerSharePaid) = ICreditManager(_creditManager).users(_recipient);

        if (totalShares > 0) {
            accRewardPerShare = accRewardPerShare + (unclaimed * PRECISION) / totalShares;
            rewards = rewards + ((accRewardPerShare - rewardPerSharePaid) * shares) / PRECISION;
        }

        return rewards;
    }

    function balanceOf(address _creditManager, address _recipient) external view returns (uint256) {
        return ICreditManager(_creditManager).pendingRewards(_recipient);
    }
}

