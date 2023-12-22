// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentTreasuryErc20.sol";
import "./ComponentVestingRefillable.sol";

contract ArbiMatTreasury is ComponentTreasuryErc20 {
    constructor(address _addressManagedToken) ComponentTreasuryErc20(_addressManagedToken) {}
}

contract ArbiMatTreasuryMarketing is ArbiMatTreasury {
    constructor(address _addressManagedToken) ArbiMatTreasury(_addressManagedToken) {}

    function rewardContributor(address _vestingAddress, address _recipientAddress, uint256 _amount) public onlyOwner {
        ComponentVestingRefillable vesting = ComponentVestingRefillable(_vestingAddress);
        managedToken.approve(_vestingAddress, _amount);
        vesting.depositTokensFrom(address(this), _recipientAddress, _amount);
    }
}

