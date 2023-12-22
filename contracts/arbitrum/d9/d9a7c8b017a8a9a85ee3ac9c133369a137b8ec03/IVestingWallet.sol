//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

interface IVestingWallet {
    function addVestingSchedule(address _investor, uint256 _amount) external;

    function release() external;
}

