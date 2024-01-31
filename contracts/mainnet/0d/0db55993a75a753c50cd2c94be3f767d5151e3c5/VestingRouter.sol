// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./math_SafeMath.sol";
import "./ReentrancyGuard.sol";

contract VestingRouter {

    address[] public _vestingAddress;
    uint[] public _vestingAmount;
    uint public lastAllocatedAddress;
    IERC20 private _stakeborgToken;

    constructor (address[] memory vestingAddresses, uint[] memory vestingAmount, address stakeborgTokenAddress) public {
        _vestingAddress = vestingAddresses;
        _vestingAmount = vestingAmount;
        _stakeborgToken = IERC20(stakeborgTokenAddress);
    }

    function allocateVestingFunds () public {
        for (uint i = lastAllocatedAddress; i < _vestingAddress.length; i++) {
            if (_stakeborgToken.balanceOf(address(this)) < _vestingAmount[i] || gasleft() < 20000) {
                break;
            }
            lastAllocatedAddress++;
            _stakeborgToken.transfer(_vestingAddress[i], _vestingAmount[i]);
        }
    }

    fallback () external { allocateVestingFunds(); }
}

