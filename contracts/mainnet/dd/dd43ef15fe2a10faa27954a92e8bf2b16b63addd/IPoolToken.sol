// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import { IERC20Permit } from "./draft-IERC20Permit.sol";

import { IERC20Burnable } from "./IERC20Burnable.sol";
import { Token } from "./Token.sol";

import { IVersioned } from "./IVersioned.sol";
import { IOwned } from "./IOwned.sol";

/**
 * @dev Pool Token interface
 */
interface IPoolToken is IVersioned, IOwned, IERC20, IERC20Permit, IERC20Burnable {
    /**
     * @dev returns the address of the reserve token
     */
    function reserveToken() external view returns (Token);

    /**
     * @dev increases the token supply and sends the new tokens to the given account
     *
     * requirements:
     *
     * - the caller must be the owner of the contract
     */
    function mint(address recipient, uint256 amount) external;
}

