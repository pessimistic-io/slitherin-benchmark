// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ILendVault.sol";
import "./IAddressProvider.sol";
import "./ILendVaultStorage.sol";

contract LendVaultStorage is ILendVaultStorage {

    /// @notice Token data for each token
    mapping (address=>TokenData) public tokenData;

    /// @notice Interest rate model data for each token
    mapping (address=>IRMData) public irmData;

    /// @notice Mapping from token to borrower to share of total debt
    /// @dev debtShare is calculated as: debtShare = debt*PRECISION/totalDebt
    mapping (address=>mapping(address=>uint)) public debtShare;

    /// @notice Mapping from token to borrower to amount of tokens that can be borrowed
    /// @dev The credit limit represents the fraction of tokens that a borrower can borrow
    /// @dev Sum of all credit limits for a token should be less than PRECISION
    mapping (address=>mapping(address=>uint)) public creditLimits;

    /// @notice Mapping from borrowers to the list of tokens that they have borrowed or can borrow
    mapping (address=>address[]) public borrowerTokens;

    /// @notice mapping from tokens to addresses that have borrowed or can borrow the token
    mapping (address=>address[]) public tokenBorrowers;

    /// @notice Array of all tokens that have been initialized
    address[] public supportedTokens;

    /// @notice The minimum health that a borrower must have in order to not have its funds siezed
    uint public healthThreshold;

    /// @notice Max utilization rate that can be reached beyond which borrowing will be reverted
    uint public maxUtilization;

    /// @notice Slppage used when using swapper
    uint public slippage;

    /// @notice Fee charged to a lender for withdrawing a large amount that requires the strategies to be delevered
    /// @dev The fee will be used as gas fee for the transactions to adjust the leverage of the strategies by the keeper
    uint public deleverFeeETH;

    /// @notice Mapping from tokens to borrowers to whitelist status
    mapping(address=>mapping(address=>bool)) public borrowerWhitelist;
    
    /// @notice Interest rate model data for each token
    mapping (address=>IRMDataMultiSlope) public irmData2;
}
