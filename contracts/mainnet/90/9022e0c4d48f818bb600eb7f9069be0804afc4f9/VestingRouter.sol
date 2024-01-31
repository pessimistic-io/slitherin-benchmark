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
    IERC20 private _bond;

    constructor (address[] memory vestingAddresses, uint[] memory vestingAmount, address bondToken) public {
        _vestingAddress = vestingAddresses;
        _vestingAmount = vestingAmount;
        _bond = IERC20(bondToken);
    }

    function allocateVestingFunds () public {
        for (uint i = lastAllocatedAddress; i < _vestingAddress.length; i++) {
            if (_bond.balanceOf(address(this)) < _vestingAmount[i] || gasleft() < 20000) {
                break;
            }
            lastAllocatedAddress++;
            _bond.transfer(_vestingAddress[i], _vestingAmount[i]);
        }
    }

    fallback () external { allocateVestingFunds(); }
}

