// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { IERC173Events } from "./IERC173Events.sol";

/**
 * @title Contract ownership standard interface
 * @dev see https://eips.ethereum.org/EIPS/eip-173
 */
interface IERC173 is IERC173Events {
    /**
     * @notice get the ERC173 contract owner
     * @return contract owner
     */
    function owner() external view returns (address);

    /**
     * @notice renounce ownership of the contract
     */
    function renounceOwnership() external;

    /**
     * @notice transfer contract ownership to new account
     * @param account address of new owner
     */
    function transferOwnership(address account) external;
}

