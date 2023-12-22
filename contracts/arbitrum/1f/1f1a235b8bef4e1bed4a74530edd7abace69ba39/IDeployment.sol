// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IDeployment {
    /**
     * @notice deposit from the treasury into the strategy
     */
    function deposit(uint256 amount, bool fromTreasury) external;

    /**
     * @notice withdraw from the strategy and return to the treasury
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice withdraw all funds from the strategy and harvest rewards    
     */
    function withdrawAll(bool dumpTokensForWeth) external; 
    
    /**
     * @notice retrieve all available rewards
     */
    function harvest(bool dumpTokensForWeth) external;

    /**
     * @notice harvests rewards and reinvests them
     */
    function compound() external;

    /**
     * @notice returns the balance of a token in the deployment
     */
    function balance(address token) external returns (uint256);

    /**
     * @notice return the amount of rewards waiting to be harvested
     */
    function pendingRewards(address token) external returns (uint256);

    /**
     * @notice withdraw tokens from the contract to the sender
     */
    function rescueToken(address token) external;

    /**
     * @notice withdraw eth from the contract to the sender
     */
    function rescueETH() external;

    /**
     * @notice perform arbitrary call on behalf of contract if something really bad happens
     */
    function rescueCall(address target, string calldata signature, bytes calldata parameters) external returns(bytes memory);
}
