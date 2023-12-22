//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

/**
 * @title IWithFees.
 * @notice This interface describes the functions for managing fees in a contract.
 */
interface IWithFees {
    error OnlyFeesManagerAccess();
    error OnlyWithFees();
    error ETHTransferFailed();

    /**
     * @notice Function returns the treasury address where fees are collected.
     * @return The address of the treasury .
     */
    function treasury() external view returns (address);

    /**
     * @notice Function returns the value of the fees.
     * @return uint256 Amount of fees to pay.
     */
    function fees() external view returns (uint256);

    /**
     * @notice Function transfers the collected fees to the treasury address.
     */
    function transfer() external;
}

