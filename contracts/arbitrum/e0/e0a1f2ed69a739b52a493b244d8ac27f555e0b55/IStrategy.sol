// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/**
 * @title Platform interface to integrate with lending platform like Compound, AAVE etc.
 */
interface IStrategy {
    /**
     * @dev Deposit the given collateral to platform
     * @param _collateral collateral address
     * @param _amount Amount to deposit
     */
    function deposit(address _collateral, uint256 _amount) external;

    /**
     * @dev Withdraw given collateral from Lending platform
     */
    function withdraw(
        address _recipient,
        address _collateral,
        uint256 _amount
    ) external;

    /**
     * @dev Withdraw the interest earned of asset from the platform.
     * @param _recipient         Address to which the asset should be sent
     * @param _asset             Address of the asset
     */
    function collectInterest(
        address _recipient,
        address _asset
    ) external;

    /**
     * @dev Returns the current balance of the given collateral.
     */
    function checkBalance(address _collateral)
        external
        view
        returns (uint256 balance);

    function checkInterestEarned(address _collateral)
        external
        view
        returns (uint256 interestEarned);

    /**
     * @dev Returns bool indicating whether strategy supports collateral.
     */
    function supportsCollateral(address _collateral) external view returns (bool);

    /**
     * @dev Collect reward tokens from the Strategy.
     */
    function collectRewardToken() external;

    /**
     * @dev The address of the reward token for the Strategy.
     */
    function rewardTokenAddress() external pure returns (address);

    /**
     * @dev The threshold (denominated in the reward token) over which the
     * vault will auto harvest on allocate calls.
     */
    function rewardLiquidationThreshold() external pure returns (uint256);

    /**
     * @dev The threshold (denominated in the reward token) over which the
     * vault will auto harvest on allocate calls.
     */
    function interestLiquidationThreshold() external pure returns (uint256);
}

