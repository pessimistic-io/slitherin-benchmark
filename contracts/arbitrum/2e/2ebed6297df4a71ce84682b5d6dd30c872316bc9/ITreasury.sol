// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ITreasury {
    event Withdrawn(address asset, address receiver, uint256 amount);

    /**
     * @dev Withdraw funds from the treasury
     * @param asset Address of the asset (0 for native token)
     * @param receiver Address of the withdrawal receiver
     * @param amount The amount of funds to withdraw.
     */
    function withdraw(address asset, address receiver, uint256 amount) external;

    receive() external payable;
}

