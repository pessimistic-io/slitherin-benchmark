// SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./BaseJumperVesting.sol";

/// @title BaseJumper team vesting contract
contract BaseJumperTeamVesting is BaseJumperVesting {

    using SafeERC20 for BaseJumper;

    uint public constant TEAM_VESTING_PERIOD = 90 days;
    uint public constant TEAM_PERCENT = 15;

    constructor(address payable _baseJumper, address payable _treasury) BaseJumperVesting(_baseJumper, _treasury, TEAM_PERCENT, TEAM_VESTING_PERIOD) {}

    function _startVesting() internal override {
        baseJumper.safeTransferFrom(_msgSender(), address(this), amountToTransfer());
        uint gonBalance = baseJumper.gonBalanceOf(address(this));
        gonTotal = gonBalance;
    }

    function _claim() internal override returns (uint gonValue) {
        require(gonWithdrawn < gonTotal, "BaseJumperTeamVesting: Already withdrawn full amount");
        gonValue = _availableToClaim(_msgSender());
        gonWithdrawn += gonValue;
    }

    function _availableToClaim(address) internal override view returns (uint gonValue) {
        gonValue = _calculateClaimableAmount(gonTotal, gonWithdrawn);
    }

    function _hasVestment(address _address) internal override view returns (bool) {
        return _address == treasury;
    }
}

