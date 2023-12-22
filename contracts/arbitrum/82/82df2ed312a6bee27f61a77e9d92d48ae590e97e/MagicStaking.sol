//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";

import "./MagicStakingContracts.sol";

contract MagicStaking is Initializable, MagicStakingContracts {

    using SafeERC20Upgradeable for IMagic;

    function initialize() external initializer {
        MagicStakingContracts.__MagicStakingContracts_init();
    }

    function toggleIsDepositingPaused()
    external
    onlyAdminOrOwner
    {
        isDepositingPaused = !isDepositingPaused;
    }

    function setLockDuration(
        uint256 _lockDuration)
    external
    onlyAdminOrOwner
    {
        lockDuration = _lockDuration;
    }

    function deposit(
        address _user,
        uint128 _amount)
    external
    whenNotPaused
    contractsAreSet
    onlyWartlocksHallow
    {

        require(!isDepositingPaused, "MagicStaking: Depositing is paused");
        require(_amount > 0, "MagicStaking: Bad amount");

        userToStakeInfo[_user].stakeAmount += _amount;
        userToStakeInfo[_user].unlockTime = uint128(block.timestamp + lockDuration);

        totalMagicStaked += _amount;

        magic.safeTransferFrom(_user, address(this), _amount);

        emit Deposit(_user, _amount, userToStakeInfo[_user].unlockTime);
    }

    function withdraw(
        address _user)
    external
    onlyWartlocksHallow
    whenNotPaused
    contractsAreSet
    {
        uint128 _amount = userToStakeInfo[_user].stakeAmount;
        require(_amount > 0, "MagicStaking: Nothing to withdraw");

        uint128 _unlockTime = userToStakeInfo[_user].unlockTime;
        require(_unlockTime <= block.timestamp, "MagicStaking: Magic is not unlocked");

        delete userToStakeInfo[_user];

        totalMagicStaked -= _amount;

        magic.safeTransfer(_user, _amount);

        emit Withdrawl(_user, _amount);
    }

    function stakeAmount(address _user) external view returns(uint128) {
        return userToStakeInfo[_user].stakeAmount;
    }

    modifier onlyWartlocksHallow() {
        require(msg.sender == address(wartlocksHallow), "MagicStaking: Only Wartlock's Hallow can call");

        _;
    }
}
