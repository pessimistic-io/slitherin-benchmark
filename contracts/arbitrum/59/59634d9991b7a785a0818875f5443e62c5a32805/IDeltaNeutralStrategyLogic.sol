// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAToken} from "./IAToken.sol";
import {IVariableDebtToken} from "./IVariableDebtToken.sol";

/// @title IDeltaNeutralStrategyLogic - DeltaNeutralStrategyLogic interface
interface IDeltaNeutralStrategyLogic {
    // =========================
    // Storage
    // =========================

    /// @dev Struct defining the delta neutral strategy storage elements.
    struct DeltaNeutralStrategyStorage {
        uint256 uniswapV3NftId;
        IAToken supplyTokenAave;
        IVariableDebtToken debtTokenAave;
        uint256 targetHealthFactor_e18;
        bytes32 pointerToAaveChecker;
        bool initialized;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when a deposit is made in the strategy.
    event DeltaNeutralStrategyDeposit();

    /// @notice Emits when a withdrawal is made from the strategy.
    event DeltaNeutralStrategyWithdraw();

    /// @notice Emits when the strategy is rebalanced.
    event DeltaNeutralStrategyRebalance();

    /// @notice Emits when the strategy is initialized.
    event DeltaNeutralStrategyInitialize();

    /// @notice Emits when a new health factor is set.
    event DeltaNeutralStrategyNewHealthFactor(uint256 newTargetHealthFactor);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when trying to initialize an already initialized strategy.
    error DeltaNeutralStrategy_AlreadyInitialized();

    /// @notice Thrown when accessing an uninitialized strategy.
    error DeltaNeutralStrategy_NotInitialized();

    /// @notice Thrown when the Aave checker is not initialized.
    error DeltaNeutralStrategy_AaveCheckerNotInitialized();

    /// @notice Thrown when health factor is out of bounds.
    error DeltaNeutralStrategy_HealthFactorOutOfRange();

    /// @notice Thrown when token0 is not wNative.
    error DeltaNeutralStrategy_Token0IsNotWNative();

    /// @notice Thrown when trying to deposit zero.
    error DeltaNeutralStrategy_DepositZero();

    /// @notice Thrown when NFT tokens are not supply and debt tokens.
    error DeltaNeutralStrategy_InvalidNFTTokens();

    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the delta neutral strategy.
    /// @dev Only callable by the owner or the vault itself.
    /// @param uniswapV3NftId The id of the UniswapV3 position.
    /// @param targetHealthFactor_e18 The target health factor to maintain.
    /// @param supplyTokenAave The Aave supply token address.
    /// @param debtTokenAave The Aave debt token address.
    /// @param pointerToAaveChecker The pointer to the Aave checker storage.
    /// @param pointer Pointer to the strategy's storage location.
    function initialize(
        uint256 uniswapV3NftId,
        uint256 targetHealthFactor_e18,
        address supplyTokenAave,
        address debtTokenAave,
        bytes32 pointerToAaveChecker,
        bytes32 pointer
    ) external;

    /// @notice Struct for `initializeWithMint` method
    struct InitializeWithMintParams {
        // The target health factor to maintain
        uint256 targetHealthFactor_e18;
        // The lower tick for uniswap position tick range
        int24 minTick;
        // The upper tick for uniswap position tick range
        int24 maxTick;
        // The fee tier uniswap pool
        uint24 poolFee;
        // The amount of supply token to deposit to new uniswap position
        uint256 supplyTokenAmount;
        // The amount of debt token to deposit to new uniswap position
        uint256 debtTokenAmount;
        // The supply token
        address supplyToken;
        // The debt token
        address debtToken;
        // The pointer to the Aave checker storage
        bytes32 pointerToAaveChecker;
    }

    /// @notice Initializes the delta neutral strategy and mints an dex NFT.
    /// @dev Only callable by the owner or the vault itself.
    /// @param p The parameters required for initialization with mint.
    /// @param pointer Pointer to the strategy's storage location.
    function initializeWithMint(
        InitializeWithMintParams memory p,
        bytes32 pointer
    ) external;

    // =========================
    // Getters
    // =========================

    /// @notice Fetches the health factors for the strategy.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return targetHF The target health factor set for the strategy.
    /// @return currentHF The current health factor of the strategy.
    /// @return uniswapV3NftId The id of the UniswapV3 position which involved to DNS.
    function healthFactorsAndNft(
        bytes32 pointer
    )
        external
        view
        returns (uint256 targetHF, uint256 currentHF, uint256 uniswapV3NftId);

    /// @notice Fetches the total supply token balance.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return The total balance of the supply token.
    function getTotalSupplyTokenBalance(
        bytes32 pointer
    ) external view returns (uint256);

    // =========================
    // Setters
    // =========================

    /// @notice Set a new target health factor.
    /// @param newTargetHF The new target health factor.
    /// @param pointer Pointer to the strategy's storage location.
    function setNewTargetHF(uint256 newTargetHF, bytes32 pointer) external;

    /// @notice Updates the NFT ID used by the strategy.
    /// @param newNftId The new NFT ID to set for the strategy.
    /// @param deviationThresholdE18 The allowable deviation before rebalancing.
    /// @param pointer Pointer to the strategy's storage location.
    function setNewNftId(
        uint256 newNftId,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Deposits tokens to startegy.
    /// @param amountToDeposit The amount of tokens to deposit.
    /// @param deviationThresholdE18 The allowable deviation before rebalancing.
    /// @param pointer Pointer to the strategy's storage location.
    function deposit(
        uint256 amountToDeposit,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external;

    /// @notice Deposits Native currency (converted to Wrapped) to startegy.
    /// @param amountToDeposit The amount of Native currency to deposit.
    /// @param deviationThresholdE18 The allowable deviation before rebalancing.
    /// @param pointer Pointer to the strategy's storage location.
    function depositETH(
        uint256 amountToDeposit,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external;

    /// @notice Withdraws a percentage share from the leveraged Uniswap position.
    /// @param shareE18 Share to withdraw (in %, 1e18 = 100%).
    /// @param deviationThresholdE18 Deviation threshold for the operation.
    /// @param pointer Pointer to the desired storage.
    function withdraw(
        uint256 shareE18,
        uint256 deviationThresholdE18,
        bytes32 pointer
    ) external;

    /// @notice Rebalance leverage uniswap to target health factor.
    /// @param deviationThresholdE18 Deviation threshold for the operation.
    /// @param pointer Pointer to the desired storage.
    function rebalance(uint256 deviationThresholdE18, bytes32 pointer) external;
}

