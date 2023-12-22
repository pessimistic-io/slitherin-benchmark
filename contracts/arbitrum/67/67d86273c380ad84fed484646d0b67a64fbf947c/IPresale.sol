// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

import "./ERC20_IERC20.sol";

/**
 * @title KEI finance Presale Contract.
 * @author KEI finance
 * @notice A fund raising contract for initial token offering.
 */
interface IPresale {
    /**
     * @notice Emitted when the {PresaleConfig} is updated.
     * @param newConfig The new presale configuration.
     * @param sender The message sender that triggered the event.
     */
    event ConfigUpdate(PresaleConfig newConfig, address indexed sender);

    /**
     * @notice Emitted when the withdrawTo value has been updated.
     * @param newWithdrawTo The previous withdrawTo address
     * @param sender The message sender that triggered the event.
     */
    event WithdrawToUpdate(address newWithdrawTo, address indexed sender);

    /**
     * @notice Emitted when the {RoundConfig} array is updated.
     * @param newRounds The previous array of round configurations.
     * @param sender The message sender that triggered the event.
     */
    event RoundsUpdate(RoundConfig[] newRounds, address indexed sender);

    /**
     * @notice Emitted when the presale has either finished or manually been closed
     */
    event Close();

    /**
     * @notice Emitted when a purchase in a round is made.
     * @param receiptId The ID of the receipt that this purchase is tied to.
     * @param roundIndex The round index that the purchase was made in.
     * @param account The account who will receive the tokens.
     * @param assetAmount The amount of assets to purchase with.
     * @param tokensAllocated The number of tokens allocated to the purchaser.
     */
    event Purchase(
        uint256 indexed receiptId,
        uint256 indexed roundIndex,
        address indexed account,
        uint256 assetAmount,
        uint256 tokensAllocated
    );

    /**
     * @notice Emitted when a purchase is made.
     * @param id The receipt ID.
     * @param account The account who will receive the tokens.
     * @param assetAmount The amount of assets to purchase with.
     * @param receipt The receipt details.
     * @param sender The message sender that triggered the event.
     */
    event PurchaseReceipt(
        uint256 indexed id, address indexed account, uint256 assetAmount, Receipt receipt, address indexed sender
    );

    /**
     * @notice Presale Configuration structure.
     * @param minDepositAmount The minimum amount of assets to purchase with.
     * @param maxUserAllocation The maximum number of tokens a user can purchase across all rounds.
     * @param startDate The unix timestamp marking the start of the presale.
     */
    struct PresaleConfig {
        uint256 minDepositAmount;
        uint256 maxUserAllocation;
        uint48 startDate;
    }

    /**
     * @notice Round Configuration structure.
     * @param tokenPrice The round token price.
     * @param tokenAllocation The number of tokens allocated for purchase in the round.
     * @param roundType The type of the round.
     */
    struct RoundConfig {
        uint256 price;
        uint256 allocation;
    }

    /**
     * @notice Purchase Configuration structure.
     * @param assetAmount The amount of the asset the user intends to spend.
     * @param account The account that will be be allocated tokens.
     */
    struct PurchaseConfig {
        uint256 assetAmount;
        address account;
    }

    /**
     * @notice Receipt structure.
     * @param id The receipt ID.
     * @param tokensAllocated The number of tokens allocated.
     * @param refundedAssets The number of tokens refunded.
     * @param costAssets The number of assets spent.
     */
    struct Receipt {
        uint256 id;
        uint256 tokensAllocated;
        uint256 refundedAssets;
        uint256 costAssets;
    }

    /**
     * @dev Cache structure to save on stack size too deep errors
     */
    struct PurchaseCache {
        uint256 totalTokenAllocation;
        uint256 totalLiquidityAllocation;
        uint256 totalRounds;
        uint256 remainingAssets;
        uint256 userAllocationRemaining;
        uint256 currentIndex;
        uint256 roundAllocationRemaining;
        uint256 userAllocation;
    }

    /**
     * @notice The PRESALE_ASSET used for purchasing the KEI tokens
     */
    function PRESALE_ASSET() external view returns (IERC20);

    /**
     * @notice The token which will be received when making a purchase
     */
    function PRESALE_TOKEN() external view returns (IERC20);

    /**
     * @notice The 8 decimal precision used in the contract.
     */
    function PRECISION() external view returns (uint256);

    /**
     * @notice Returns the current round index.
     */
    function currentRoundIndex() external view returns (uint256);

    /**
     * @notice Returns the presale configuration.
     */
    function config() external view returns (PresaleConfig memory);

    /**
     * @notice Returns where the funds will be sent on a successful purchase.
     */
    function withdrawTo() external view returns (address);

    /**
     * @notice Returns whether or not the presale has ended
     */
    function closed() external view returns (bool);

    /**
     * @notice Returns the configuration of a specific round.
     * @param roundIndex The round index to return the configuration of.
     */
    function round(uint256 roundIndex) external view returns (RoundConfig memory);

    /**
     * @notice Returns an array of all the round configurations set by the admin.
     */
    function rounds() external view returns (RoundConfig[] memory);

    /**
     * @notice Returns the number of total purchases made.
     */
    function totalPurchases() external view returns (uint256);

    /**
     * @notice Returns the number of total rounds.
     */
    function totalRounds() external view returns (uint256);

    /**
     * @notice Returns the total amount of presale assets raised
     */
    function totalRaised() external view returns (uint256);

    /**
     * @notice Returns the number of tokens allocated in a round.
     * @param roundIndex The index of the round to return the tokens allocated in.
     */
    function roundTokensAllocated(uint256 roundIndex) external view returns (uint256);

    /**
     * @notice Returns the number of tokens allocated to a specific user across `Token` type rounds.
     * @param account The account to return the token allocation of.
     */
    function userTokensAllocated(address account) external view returns (uint256);

    /**
     * @notice Returns the conversion from assets to tokens. Where assets is the PRESALE_ASSET
     * @param amount The amount of assets to convert.
     * @param price The price of tokens - based on the current round price set by admin.
     * @return tokenAmount The number of tokens that are equal to the value of input assets.
     */
    function assetsToTokens(uint256 amount, uint256 price) external pure returns (uint256 tokenAmount);

    /**
     * @notice Returns the conversion from tokens to assets.
     * @param amount The amount of tokens to convert.
     * @param price The price of tokens - based on the current round price set by admin.
     * @return assetAmount The assets value of the input tokens.
     */
    function tokensToAssets(uint256 amount, uint256 price) external pure returns (uint256 assetAmount);

    /**
     * @notice Closes the Presale early, before all the rounds have been complete
     * @dev emits Close
     * @dev The function caller must be the owner of the contract.
     * @dev The contract must not already be closed.
     */
    function close() external;

    /**
     * @notice Updates where the presale tokens will be sent
     * @param newWithdrawTo The new withdraw to address
     * @dev emits WithdrawToUpdate
     * @dev The function caller must be the owner of the contract.
     */
    function setWithdrawTo(address newWithdrawTo) external;

    /**
     * @notice Purchases tokens for `account`, by spending PRESALE_ASSETs. Will continue to purchase through each
     * round until all the funds or the max user allocation has been hit.
     * @param account The account who will receive the tokens.
     * @param assetAmount The amount of assets to purchase with.
     * @dev emits Purchase - for each round that the purchase is made within
     * @dev emits PurchaseReceipt
     * @dev reverts if the contract is closed.
     * @dev reverts if the current block timestamp is less than the `startDate`.
     * @dev reverts if the asset value is 0 or less than the minimum deposit amount
     * @dev reverts if there are no tokens allocated
     * @return The receipt.
     */
    function purchase(address account, uint256 assetAmount) external returns (Receipt memory);

    /**
     * @notice Initializes the presale contract with the given configurations
     * @param newWithdrawTo where the asset will be transferred to on purchase
     * @param newConfig the presale configuration
     * @param newRounds the round configuration for the presale
     */
    function initialize(address newWithdrawTo, PresaleConfig memory newConfig, RoundConfig[] memory newRounds)
        external;
}

