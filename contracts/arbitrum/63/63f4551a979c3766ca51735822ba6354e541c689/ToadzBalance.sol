//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzBalanceContracts.sol";

contract ToadzBalance is Initializable, ToadzBalanceContracts {

    function initialize() external initializer {
        ToadzBalanceContracts.__ToadzBalanceContracts_init();
    }

    function balanceOf(
        address _owner)
    external
    view
    contractsAreSet
    returns(uint256)
    {
        return toadz.balanceOf(_owner) + world.balanceOf(_owner);
    }
}
