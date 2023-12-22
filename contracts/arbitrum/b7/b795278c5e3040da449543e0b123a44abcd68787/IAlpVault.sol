// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAlpVault {
    /**
     * @dev Struct representing user-specific information for a position in the strategy.
     */
    struct UserInfo {
        address user; // User's address.
        uint256 deposit; // Amount deposited by the user.
        uint256 leverage; // Leverage applied to the position.
        uint256 position; // Current position size.
        uint256 price; // Price of the asset at the time of the transaction.
        bool liquidated; // Flag indicating if the position has been liquidated.
        uint256 closedPositionValue; // Value of the closed position.
        address liquidator; // Address of the liquidator, if liquidated.
        uint256 closePNL; // Profit and Loss from closing the position.
        uint256 leverageAmount; // Amount leveraged in the position.
        uint256 positionId; // Unique identifier for the position.
        bool closed; // Flag indicating if the position is closed.
    }

    /**
     * @dev Struct used to store intermediate data during position closure calculations.
     */
    struct CloseData {
        uint256 returnedValue; // The amount returned after position closure.
        uint256 profits; // The profits made from the closure.
        uint256 originalPosAmount; // The original position amount.
        uint256 waterRepayment; // The amount repaid to the lending protocol.
        uint256 waterProfits; // The profits received from the lending protocol.
        uint256 mFee; // Management fee.
        uint256 userShares; // Shares allocated to the user.
        uint256 toLeverageUser; // Amount provided to the user after leverages.
        uint256 currentDTV; // Current debt-to-value ratio.
        bool success; // Flag indicating the success of the closure operation.
    }

    // @dev StrategyAddresses struct represents addresses used in the strategy
    struct StrategyAddresses {
        address alpDiamond; // ALP Diamond contract
        address smartChef; // Stake ALP
        address apolloXP; // ApolloX token contract
        address masterChef; // ALP-vodka MasterChef contract
        address alpRewardHandler; // ALP Reward Handler contract
    }

    // @dev StrategyMisc struct represents miscellaneous parameters of the strategy
    struct StrategyMisc {
        uint256 MAX_LEVERAGE; // Maximum allowed leverage
        uint256 MIN_LEVERAGE; // Minimum allowed leverage
        uint256 DECIMAL; // Decimal precision
        uint256 MAX_BPS; // Maximum basis points
    }

    // @dev FeeConfiguration struct represents fee-related parameters of the strategy
    struct FeeConfiguration {
        address feeReceiver; // Fee receiver address
        uint256 withdrawalFee; // Withdrawal fee amount
        address waterFeeReceiver; // Water fee receiver address
        uint256 liquidatorsRewardPercentage; // Liquidator's reward percentage
        uint256 fixedFeeSplit; // Fixed fee split amount
    }

    event SetWhitelistedAsset(address token, bool status);
    event SetStrategyAddresses(address diamond, address alpManager, address apolloXP);
    event SetFeeConfiguration(
        address feeReceiver,
        uint256 withdrawalFee,
        address waterFeeReceiver,
        uint256 liquidatorsRewardPercentage,
        uint256 fixedFeeSplit
    );
    event CAKEHarvested(uint256 amount);

    /**
     * @dev Emitted when a position is opened.
     * @param user The address of the user who opened the position.
     * @param leverageSize The size of the leverage used for the position.
     * @param amountDeposited The amount deposited by the user.
     * @param podAmountMinted The amount of POD tokens minted for the position.
     * @param positionId The ID of the position opened.
     * @param time The timestamp when the position was opened.
     */
    event OpenPosition(
        address indexed user,
        uint256 leverageSize,
        uint256 amountDeposited,
        uint256 podAmountMinted,
        uint256 positionId,
        uint256 time
    );

    /**
     * @dev Emitted when a position is closed.
     * @param user The address of the user who closed the position.
     * @param amountAfterFee The amount remaining after fees are deducted.
     * @param positionId The ID of the closed position.
     * @param timestamp The timestamp when the position was closed.
     * @param position The final position after closure.
     * @param leverageSize The size of the leverage used for the position.
     * @param time The timestamp of the event emission.
     */
    event ClosePosition(address user, uint256 amountAfterFee, uint256 positionId, uint256 timestamp, uint256 position, uint256 leverageSize, uint256 time);

    /**
     * @dev Emitted when a position is liquidated.
     * @param user The address of the user whose position is liquidated.
     * @param positionId The ID of the liquidated position.
     * @param liquidator The address of the user who performed the liquidation.
     * @param returnedAmount The amount returned after liquidation.
     * @param liquidatorRewards The rewards given to the liquidator.
     * @param time The timestamp of the liquidation event.
     */
    event Liquidated(address user, uint256 positionId, address liquidator, uint256 returnedAmount, uint256 liquidatorRewards, uint256 time);
    event SetBurner(address indexed burner, bool allowed);
    event SetAllowedClosers(address indexed closer, bool allowed);
    event SetAllowedSenders(address indexed sender, bool allowed);
    event MigrateLP(address indexed newLP, uint256 amount);

    /**
     * @dev Opens a new position.
     * @param _token The address of the token for the position.
     * @param _amount The amount of tokens to be used for the position.
     * @param _leverage The leverage multiplier for the position.
     *
     * Requirements:
     * - `_leverage` must be within the range of MIN_LEVERAGE to MAX_LEVERAGE.
     * - `_amount` must be greater than zero.
     * - `_token` must be whitelisted.
     *
     * Steps:
     * - Transfers `_amount` of tokens from the caller to this contract.
     * - Uses Water contract to lend a leveraged amount based on the provided `_amount` and `_leverage`.
     * - Mints Alp tokens using `_token` and `sumAmount` to participate in ApolloX.
     * - Deposits minted Alp tokens into the SmartChef contract.
     * - Records user information including deposit, leverage, position, etc.
     * - Mints POD tokens for the user.
     *
     * Emits an OpenPosition event with relevant details.
     */
    function openPosition(address _token, uint256 _amount, uint256 _leverage) external;

    /**
     * @dev Closes a position based on provided parameters.
     * @param positionId The ID of the position to close.
     * @param _user The address of the user holding the position.
     *
     * Requirements:
     * - Position must not be liquidated.
     * - Position must have enough shares to close.
     * - Caller must be allowed to close the position or must be the position owner.
     *
     * Steps:
     * - Retrieves user information for the given position.
     * - Validates that the position is not liquidated and has enough shares to close.
     * - Handles the POD token for the user.
     * - Withdraws the staked amount from the Smart Chef contract.
     * - Burns Alp tokens to retrieve USDC based on the position amount.
     * - Calculates profits, water repayment, and protocol fees.
     * - Repays the Water contract if the position is not liquidated.
     * - Transfers profits, fees, and protocol fees to the respective receivers.
     * - Takes protocol fees if applicable and emits a ClosePosition event.
     */
    function closePosition(uint256 positionId, address _user) external;

    /**
     * @dev Liquidates a position based on provided parameters.
     * @param _positionId The ID of the position to be liquidated.
     * @param _user The address of the user owning the position.
     *
     * Requirements:
     * - Position must not be already liquidated.
     * - Liquidation request must exist for the provided user.
     * - Liquidation should not exceed the predefined debt-to-value limit.
     *
     * Steps:
     * - Retrieves user information for the given position.
     * - Validates the position for liquidation based on the debt-to-value limit.
     * - Handles the POD token for the user.
     * - Burns Alp tokens to retrieve USDC based on the position amount.
     * - Calculates liquidator rewards and performs debt repayment to the Water contract.
     * - Transfers liquidator rewards and emits a Liquidated event.
     */
    function liquidatePosition(uint256 _positionId, address _user) external;

    /**
     * @dev Retrieves the current position and its previous value in USDC for a user's specified position.
     * @param _positionID The identifier for the user's position.
     * @param _shares The number of shares for the position.
     * @param _user The user's address.
     * @return currentPosition The current position value in USDC.
     * @return previousValueInUSDC The previous position value in USDC.
     */
    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) external view returns (uint256 currentPosition, uint256 previousValueInUSDC);

    /**
     * @dev Retrieves the updated debt values for a user's specified position.
     * @param _positionID The identifier for the user's position.
     * @param _user The user's address.
     * @return currentDTV The current Debt to Value (DTV) ratio.
     * @return currentPosition The current position value in USDC.
     * @return currentDebt The current amount of debt associated with the position.
     */
    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) external view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt);

    /**
     * @dev Retrieves the cooling duration of the APL token from the AlpManagerFacet.
     * @return The cooling duration in seconds.
     */
    function getAlpCoolingDuration() external view returns (uint256);

    /**
     * @dev Retrieves an array containing all registered user addresses.
     * @return An array of all registered user addresses.
     */
    function getAllUsers() external view returns (address[] memory);

    /**
     * @dev Retrieves the total number of open positions associated with a specific user.
     * @param _user The user's address.
     * @return The total number of open positions belonging to the specified user.
     */
    function getTotalNumbersOfOpenPositionBy(address _user) external view returns (uint256);

    /**
     * @dev Retrieves the current price of the APL token from the AlpManagerFacet.
     * @return The current price of the APL token.
     */
    function getAlpPrice() external view returns (uint256);
}

