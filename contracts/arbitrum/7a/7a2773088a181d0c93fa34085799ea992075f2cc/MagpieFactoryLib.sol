// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {ERC20} from "./ERC20.sol";
import {MintableERC20} from "./MintableERC20.sol";
import {BaseRewardPoolV3} from "./BaseRewardPoolV3.sol";
import {WombatPoolHelperV3} from "./WombatPoolHelperV3.sol";
import {BribeRewardPool} from "./BribeRewardPool.sol";

library MagpieFactoryLib {
    function createERC20(
        string memory name_,
        string memory symbol_
    ) public returns (address) {
        ERC20 token = new MintableERC20(name_, symbol_);
        return address(token);
    }

    function createRewarder(
        address _stakingToken,
        address _mainRewardToken,
        address _masterMagpie,
        address _rewardManager
    ) external returns (address) {
        BaseRewardPoolV3 _rewarder = new BaseRewardPoolV3(
            _stakingToken,
            _mainRewardToken,
            _masterMagpie,
            _rewardManager
        );
        return address(_rewarder);
    }

    function createWombatPoolHelper(
        uint256 _pid,
        address _stakingToken,
        address _depositToken,
        address _lpToken,
        address _wombatStaking,
        address _masterMagpie,
        address _rewarder,
        address _mWom,
        bool _isNative
    ) public returns (address) {
        WombatPoolHelperV3 pool = new WombatPoolHelperV3(
            _pid,
            _stakingToken,
            _depositToken,
            _lpToken,
            _wombatStaking,
            _masterMagpie,
            _rewarder,
            _mWom,
            _isNative
        );
        return address(pool);
    }
}

