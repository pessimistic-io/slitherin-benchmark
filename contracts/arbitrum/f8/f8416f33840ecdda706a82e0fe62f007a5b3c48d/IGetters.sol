// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";

import {LibTermStorage} from "./LibTermStorage.sol";
import {LibCollateralStorage} from "./LibCollateralStorage.sol";
import {LibFundStorage} from "./LibFundStorage.sol";

interface IGetters {
    // TERM GETTERS

    /// @notice Gets the current and next term id
    /// @return current termID
    /// @return next termID
    function getTermsId() external view returns (uint, uint);

    /// @notice Must return 0 before starting the fund
    /// @param termId the id of the term
    /// @return remaining registration time in seconds
    function getRemainingRegistrationTime(uint termId) external view returns (uint);

    /// @notice Get current information of a term
    /// @param termId the id of the term
    /// @return Term Struct, see LibTermStorage.sol
    function getTermSummary(uint termId) external view returns (LibTermStorage.Term memory);

    /// @notice Gets all terms a user has previously joined
    /// @param participant address
    /// @return List of termIDs
    function getAllJoinedTerms(address participant) external view returns (uint[] memory);

    /// @notice Gets all terms a user has previously joined based on the specefied term state
    /// @param participant address
    /// @param state, can be InitializingTerm, ActiveTerm, ExpiredTerm, ClosedTerm
    /// @return List of termIDs
    function getJoinedTermsByState(
        address participant,
        LibTermStorage.TermStates state
    ) external view returns (uint[] memory);

    /// @notice Gets all terms a user was previously expelled from
    /// @param participant address
    /// @return List of termIDs
    function getExpelledTerms(address participant) external view returns (uint[] memory);

    /// @notice Gets all remaining cycles of a term
    /// @param termId the id of the term
    /// @return remaining cycles
    function getRemainingCycles(uint termId) external view returns (uint);

    /// @notice Must be 0 before starting a new cycle
    /// @param termId the id of the term
    /// @return remaining cycle time in seconds
    function getRemainingCycleTime(uint termId) external view returns (uint);

    /// @notice Gets the expected remaining contribution amount for users in a term
    /// @param termId the id of the term
    /// @return total remaining contribution in wei
    function getRemainingCyclesContributionWei(uint termId) external view returns (uint);

    /// @notice a function to get the needed allowance
    /// @param user the user address
    /// @return the needed allowance
    function getNeededAllowance(address user) external view returns (uint);

    // COLLATERAL GETTERS

    /// @notice Gets a users collateral summary
    /// @param depositor address
    /// @param termId the id of the term
    /// @return if the user is a true member of the term
    /// @return current users locked collateral balance in wei
    /// @return current users unlocked collateral balance in wei
    /// @return initial users deposit in wei
    /// @return expulsion limit
    function getDepositorCollateralSummary(
        address depositor,
        uint termId
    ) external view returns (bool, uint, uint, uint, uint);

    /// @notice Gets the collateral summary of a term
    /// @param termId the id of the term
    /// @return if collateral is initialized
    /// @return current state of the collateral, see States struct in LibCollateralStorage.sol
    /// @return time of first deposit in seconds, 0 if no deposit occured yet
    /// @return current member count
    /// @return list of depositors
    function getCollateralSummary(
        uint termId
    )
        external
        view
        returns (bool, LibCollateralStorage.CollateralStates, uint, uint, address[] memory);

    /// @notice Gets the required minimum collateral deposit based on the position
    /// @param termId the term id
    /// @param depositorIndex the index of the depositor
    /// @return required minimum in wei
    function minCollateralToDeposit(uint termId, uint depositorIndex) external view returns (uint);

    /// @notice Called to check how much collateral a user can withdraw
    /// @param termId term id
    /// @param user depositor address
    /// @return allowedWithdrawal amount the amount of collateral the depositor can withdraw
    function getWithdrawableUserBalance(
        uint termId,
        address user
    ) external view returns (uint allowedWithdrawal);

    // FUND GETTERS
    /// @notice Gets the fund summary of a term
    /// @param termId the id of the term
    /// @return if fund is initialized
    /// @return current state of the fund, see States struct in LibFund.sol
    /// @return stablecoin address used
    /// @return list for order of beneficiaries
    /// @return when the fund started in seconds
    /// @return when the fund ended in seconds, 0 otherwise
    /// @return current cycle of fund
    /// @return total amount of cycles in this fund/term
    function getFundSummary(
        uint termId
    )
        external
        view
        returns (bool, LibFundStorage.FundStates, IERC20, address[] memory, uint, uint, uint, uint);

    /// @notice Gets the current beneficiary of a term
    /// @param termId the id of the term
    /// @return user address
    function getCurrentBeneficiary(uint termId) external view returns (address);

    /// @notice Gets if a user is expelled from a specefic term
    /// @param termId the id of the term
    /// @param user address
    /// @return true or false
    function wasExpelled(uint termId, address user) external view returns (bool);

    /// @notice Gets if a user is exempted from paying for a specefic cycle
    /// @param termId the id of the term
    /// @param cycle number
    /// @param user address
    /// @return true or false
    function isExempted(uint termId, uint cycle, address user) external view returns (bool);

    /// @notice Gets a user information of in a fund
    /// @param participant address
    /// @param termId the id of the term
    /// @return if the user is a true member of the fund/term
    /// @return if the user was beneficiary in the past
    /// @return if the user paid for the current cycle
    /// @return if the user has autopay enabled
    /// @return users money pot balance
    function getParticipantFundSummary(
        address participant,
        uint termId
    ) external view returns (bool, bool, bool, bool, uint, bool);

    /// @notice Must return 0 before closing a contribution period
    /// @param termId the id of the term
    /// @return remaining contribution time in seconds
    function getRemainingContributionTime(uint termId) external view returns (uint);

    // CONVERSION GETTERS

    function getToCollateralConversionRate(uint USDAmount) external view returns (uint);

    function getToStableConversionRate(uint ethAmount) external view returns (uint);

    // YIELD GENERATION GETTERS

    function userHasoptedInYG(uint termId, address user) external view returns (bool);

    function userAPY(uint termId, address user) external returns (uint256);

    function termAPY(uint termId) external returns (uint256);

    function yieldDistributionRatio(uint termId, address user) external view returns (uint256);

    function totalYieldGenerated(uint termId) external returns (uint);

    function userYieldGenerated(uint termId, address user) external returns (uint);

    function getYieldLockState() external view returns (bool);

    /// @notice This function return the current constant values for oracles and yield providers
    /// @param firstAggregator The name of the first aggregator. Example: "ETH/USD"
    /// @param secondAggregator The name of the second aggregator. Example: "USDC/USD"
    /// @param zapAddress The name of the zap address. Example: "ZaynZap"
    /// @param vaultAddress The name of the vault address. Example: "ZaynVault"
    function getConstants(
        string memory firstAggregator,
        string memory secondAggregator,
        string memory zapAddress,
        string memory vaultAddress
    ) external view returns (address, address, address, address);
}

