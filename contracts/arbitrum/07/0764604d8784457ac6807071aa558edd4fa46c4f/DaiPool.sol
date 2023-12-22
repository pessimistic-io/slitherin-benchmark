// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: 6094467959b5f026a0b2395f84a97536afb77aab;
pragma solidity 0.8.17;

import "./Pool.sol";


/**
 * @title DaiPool
 * @dev Contract allowing user to deposit to and borrow DAI from a dedicated user account
 */
contract DaiPool is Pool {
    function name() public virtual override pure returns(string memory _name){
        _name = "DeltaPrimeDAIToken";
    }

    function symbol() public virtual override pure returns(string memory _symbol){
        _symbol = "DPDAI";
    }

    function decimals() public virtual override pure returns(uint8 decimals){
        decimals = 18;
    }
}
