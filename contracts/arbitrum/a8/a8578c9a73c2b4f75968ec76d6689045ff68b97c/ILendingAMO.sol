// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {OlympusERC20Token} from "./OlympusERC20.sol";

interface ILendingAMO {
    // ========= ERRORS ========= //

    error AMO_Inactive(address amo_);
    error AMO_LimitViolation(address amo_);
    error AMO_UnwindOnly(address amo_);
    error AMO_NotUnwinding(address amo_);
    error AMO_UpdateReentrancyGuard(address amo_);
    error AMO_UpdateInterval(address amo_);

    // ========= EVENTS ========= //

    event Deposit(uint256 amount_);
    event Withdrawal(uint256 amount_);

    // ========= STATE ========= //

    /// @notice Olympus token
    function OHM() external view returns (OlympusERC20Token);

    /// @notice Address of the external lending market
    function market() external view returns (address);

    /// @notice The maximum amount of OHM that can be minted and deployed by the contract
    function maximumToDeploy() external view returns (uint256);

    /// @notice Update interval
    function updateInterval() external view returns (uint256);

    /// @notice The amount of OHM that is currently deployed in the external lending market by the AMO
    function ohmDeployed() external view returns (uint256);

    /// @notice The amount of previously circulating OHM that has been accrued as interest and burned
    function circulatingOhmBurned() external view returns (uint256);

    /// @notice Last update call timestamp
    function lastUpdateTimestamp() external view returns (uint256);

    /// @notice Whether the AMO is active or not
    function status() external view returns (bool);

    /// @notice Whether the AMO should try to withdraw all available OHM from the external market
    function shouldEmergencyUnwind() external view returns (bool);

    //============================================================================================//
    //                                        CORE FUNCTIONS                                      //
    //============================================================================================//

    /// @notice                     Deposits OHM into the external lending market
    /// @param amount_              The amount of OHM to deposit
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function deposit(uint256 amount_) external;

    /// @notice                     Withdraws OHM from the external lending market
    /// @param amount_              The amount of OHM to withdraw
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function withdraw(uint256 amount_) external;

    /// @notice                     Updates the contract's deployment of OHM in the external lending market
    ///                             It increases or decreases the contract's deposit to achieve the external
    ///                             market's optimal utilization, but will not exceed the establish maximum deployment
    function update() external;

    /// @notice                     Harvests any yield from the external market
    function harvestYield() external;

    /// @notice                     Tells the AMO to not deposit on future update calls and withdraw all available OHM from the external lending market
    /// @dev                        Only callable by an address with the emergency_admin role
    function emergencyUnwind() external;

    /// @notice                     Sweeps any accumulated ERC20 tokens to the calling address
    /// @dev                        Only callable by an address with the lendingamo_admin role
    /// @param token_               The address of the ERC20 token to sweep
    function sweepTokens(address token_) external;

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// @notice                     Gets the AMO's claim on OHM in the external lending market (principal + accumulated interest)
    /// @return uint256             The amount of OHM that the AMO has a claim on in the external market
    function getUnderlyingOhmBalance() external view returns (uint256);

    /// @notice                     Gets the OHM value that would achieve the market's optimal utilization rate
    /// @dev                        We do this vs targeting an interest rate because every market is set up to target
    ///                             different equilibrium interest rates and fighting that seems inefficient
    /// @return uint256             The amount of OHM that would achieve the optimal utilization rate
    function getTargetDeploymentAmount() external view returns (uint256);

    /// @notice                     Gets the current amount of OHM deposited by the AMO that is currently being borrowed in the market
    /// @dev                        This is implemented based on the assumption that the protocol will behave
    ///                             as the "lender of last resort" in a sense, meaning we are likely to be the last
    ///                             withdrawer. So we can think of the current portion of our deposit that has been
    ///                             borrowed as the lesser of the total amount borrowed and the total amount we have
    ///                             deposited. This is not a perfect assumption, but it is a good enough approximation.
    /// @return uint256             The amount of OHM that is currently borrowed
    function getBorrowedOhm() external view returns (uint256);

    //============================================================================================//
    //                                        ADMIN FUNCTIONS                                     //
    //============================================================================================//

    /// @notice                     Sets the maximum amount of OHM that can be deployed by the contract
    /// @param newMaximum_          The new maximum amount of OHM that can be deployed
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function setMaximumToDeploy(uint256 newMaximum_) external;

    /// @notice                     Sets the update interval
    /// @param newInterval_         The new update interval
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function setUpdateInterval(uint256 newInterval_) external;

    /// @notice                     Activates the AMO
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function activate() external;

    /// @notice                     Deactivates the AMO
    /// @dev                        Only callable by an address with the lendingamo_admin role
    function deactivate() external;
}

