// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: b75e073cf23a3eb181f55a89a800ef040b7ba456;
pragma solidity 0.8.17;

import "./Pool.sol";


/**
 * @title UsdcPool
 * @dev Contract allowing user to deposit to and borrow USDC from a dedicated user account
 */
contract UsdcPool is Pool {
    function name() public virtual override pure returns(string memory _name){
        _name = "DeltaPrimeUSDCoin";
    }

    function symbol() public virtual override pure returns(string memory _symbol){
        _symbol = "DPUSDC";
    }

    function decimals() public virtual override pure returns(uint8 decimals){
        decimals = 6;
    }
}
