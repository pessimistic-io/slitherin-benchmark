//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IMagicStaking.sol";
import "./IWartlocksHallow.sol";
import "./IMagic.sol";
import "./AdminableUpgradeable.sol";

abstract contract MagicStakingState is Initializable, IMagicStaking, AdminableUpgradeable {

    event Deposit(address indexed _user, uint128 _amount, uint128 _unlockTime);
    event Withdrawl(address indexed _user, uint128 _amount);

    IMagic public magic;
    IWartlocksHallow public wartlocksHallow;

    mapping(address => UserStakeInfo) public userToStakeInfo;

    uint256 public totalMagicStaked;

    uint256 public lockDuration;

    bool public isDepositingPaused;

    function __MagicStakingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        lockDuration = 2 weeks;
    }
}

struct UserStakeInfo {
    uint128 stakeAmount;
    uint128 unlockTime;
}
