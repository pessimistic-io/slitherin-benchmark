// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";

import { IAbstractVault as IOriginAbstractVault } from "./IAbstractVault.sol";
import { IVerificationRuler } from "./IVerificationRuler.sol";
import { IStorageAddresses } from "./IStorageAddresses.sol";
import { IBaseReward as IOriginBaseReward } from "./IBaseReward.sol";

interface IAbstractVault is IOriginAbstractVault, IERC20 {
    function creditManagersCount() external view returns (uint256);

    function creditManagers(uint256 _idx) external view returns (address);
}

contract VerificationRuler is IVerificationRuler, Ownable {
    uint256 public maxRatio = 90;

    event SetMaxRatio(uint256 _maxRatio);

    constructor(uint256 _maxRatio) {
        maxRatio = _maxRatio;
    }

    function setMaxRatio(uint256 _maxRatio) public onlyOwner {
        require(_maxRatio > 50, "VerificationRuler: The maximum ratio must be greater than 50");

        maxRatio = _maxRatio;

        emit SetMaxRatio(maxRatio);
    }

    function canBorrow(address _vault, uint256 _borrowedAmount) external view override returns (bool) {
        uint256 creditManagersCount = IAbstractVault(_vault).creditManagersCount();
        address rewardPools = IAbstractVault(_vault).rewardPools();
        address supplyRewardPool = IStorageAddresses(rewardPools).getAddress(_vault);
        uint256 denominator = IAbstractVault(_vault).balanceOf(supplyRewardPool);
        uint256 numerator = _borrowedAmount;

        address[] memory borrowedRewardPools = new address[](creditManagersCount);

        for (uint256 i = 0; i < creditManagersCount; i++) {
            address creditManager = IAbstractVault(_vault).creditManagers(i);
            address borrowedRewardPool = IStorageAddresses(rewardPools).getAddress(creditManager);

            for (uint256 j = 0; j < borrowedRewardPools.length; j++) {
                if (borrowedRewardPools[j] == borrowedRewardPool) break;
                else borrowedRewardPools[i] = borrowedRewardPool;
            }
        }

        for (uint256 i = 0; i < borrowedRewardPools.length; i++) {
            if (borrowedRewardPools[i] == address(0)) continue;
            numerator += IAbstractVault(_vault).balanceOf(borrowedRewardPools[i]);
        }

        uint256 ratio = (((numerator * 1e18) / denominator) * 100) / 1e18;

        if (ratio >= maxRatio) return false;

        return true;
    }
}

