// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20Upgradeable.sol";

import "./ISavvySwap.sol";
import "./ISavvyPositionManager.sol";
import "./IERC20TokenReceiver.sol";

/// @title  ISavvySage
/// @author Savvy DeFi
interface ISavvySage is IERC20TokenReceiver {
    /// @notice Parameters used to define a given weighting schema.
    ///
    /// Weighting schemas can be used to generally weight tokens in relation to an action or actions that will be taken.
    /// In the SavvySage, there are 2 actions that require weighting schemas: `burnCredit` and `depositFunds`.
    ///
    /// `burnCredit` uses a weighting schema that determines which yield-tokens are targeted when burning credit from
    /// the `Account` controlled by the SavvySage, via the `Savvy.donate` function.
    ///
    /// `depositFunds` uses a weighting schema that determines which yield-tokens are targeted when depositing
    /// base tokens into the Savvy.
    struct Weighting {
        // The weights of the tokens used by the schema.
        mapping(address => uint256) weights;
        // The tokens used by the schema.
        address[] tokens;
        // The total weight of the schema (sum of the token weights).
        uint256 totalWeight;
    }

    /// @notice Emitted when the savvy is set.
    ///
    /// @param savvy The address of the savvy.
    event SetSavvy(address savvy);

    /// @notice Emitted when the slippage is set.
    event SlippageRateSet(uint16 _slippageRate);

    /// @notice Emitted when the amo is set.
    ///
    /// @param baseToken The address of the base token.
    /// @param amo             The address of the amo.
    event SetAmo(address baseToken, address amo);

    /// @notice Emitted when the the status of diverting to the amo is set for a given base token.
    ///
    /// @param baseToken The address of the base token.
    /// @param divert          Whether or not to divert funds to the amo.
    event SetDivertToAmo(address baseToken, bool divert);

    /// @notice Emitted when an base token is registered.
    ///
    /// @param baseToken The address of the base token.
    /// @param savvySwap      The address of the savvySwap for the base token.
    event RegisterToken(address baseToken, address savvySwap);

    /// @param baseToken The address of the base token.
    /// @param savvySwap      The address of the savvySwap for the base token.
    event UnregisterToken(address baseToken, address savvySwap);

    /// @notice Emitted when an base token's flow rate is updated.
    ///
    /// @param baseToken The base token.
    /// @param flowRate        The flow rate for the base token.
    event SetFlowRate(address baseToken, uint256 flowRate);

    /// @notice Emitted when the strategies are refreshed.
    event RefreshStrategies();

    /// @notice Emitted when a source is set.
    event SetSource(address source, bool flag);

    /// @notice Emitted when a savvySwap is updated.
    event SetSavvySwap(address baseToken, address savvySwap);

    /// @notice Gets the current version.
    ///
    /// @return The version.
    function version() external view returns (string memory);

    /// @notice Gets the total credit held by the SavvySage.
    ///
    /// @return The total credit.
    function getTotalCredit() external view returns (uint256);

    /// @notice Gets registered base token addresses.
    function getRegisteredBaseTokens() external view returns (address[] memory);

    /// @notice Gets the total amount of base token that the SavvySage controls in the Savvy.
    ///
    /// @param baseToken The base token to query.
    ///
    /// @return totalBuffered The total buffered.
    function getTotalUnderlyingBuffered(
        address baseToken
    ) external view returns (uint256 totalBuffered);

    /// @notice Gets the total available flow for the base token
    ///
    /// The total available flow will be the lesser of `flowAvailable[token]` and `getTotalUnderlyingBuffered`.
    ///
    /// @param baseToken The base token to query.
    ///
    /// @return availableFlow The available flow.
    function getAvailableFlow(
        address baseToken
    ) external view returns (uint256 availableFlow);

    /// @notice Gets the weight of the given weight type and token
    ///
    /// @param weightToken The type of weight to query.
    /// @param token       The weighted token.
    ///
    /// @return weight The weight of the token for the given weight type.
    function getWeight(
        address weightToken,
        address token
    ) external view returns (uint256 weight);

    /// @notice Set a source of funds.
    ///
    /// @param source The target source.
    /// @param flag   The status to set for the target source.
    function setSource(address source, bool flag) external;

    /// @notice Set savvySwap by admin.
    ///
    /// This function reverts if the caller is not the current admin.
    ///
    /// @param baseToken The target base token to update.
    /// @param newSavvySwap   The new savvySwap for the target `baseToken`.
    function setSavvySwap(address baseToken, address newSavvySwap) external;

    /// @notice Set savvy by admin.
    ///
    /// This function reverts if the caller is not the current admin.
    ///
    /// @param savvy The new savvy whose funds we are handling.
    function setSavvy(address savvy) external;

    /// @notice Set allow slippage rate.
    ///
    /// This function reverts if the caller is not the current admin.
    /// This function also reverts if slippage rate is too big. over 30%
    /// @param slippageRate The slippage percent rate.
    function setSlippageRate(uint16 slippageRate) external;

    /// @notice Set the address of the amo for a target base token.
    ///
    /// @param baseToken The address of the base token to set.
    /// @param amo The address of the base token's new amo.
    function setAmo(address baseToken, address amo) external;

    /// @notice Set whether or not to divert funds to the amo.
    ///
    /// @param baseToken The address of the base token to set.
    /// @param divert          Whether or not to divert base token to the amo.
    function setDivertToAmo(address baseToken, bool divert) external;

    /// @notice Refresh the yield-tokens in the SavvySage.
    ///
    /// This requires a call anytime governance adds a new yield token to the savvy.
    function refreshStrategies() external;

    /// @notice Register an base token.
    ///
    /// This function reverts if the caller is not the current admin.
    ///
    /// @param baseToken The base token being registered.
    /// @param savvySwap      The savvySwap for the base token.
    function registerToken(address baseToken, address savvySwap) external;

    /// @notice Unregister an base token.
    ///
    /// This function reverts if the caller is not the current admin.
    ///
    /// @param baseToken The base token being unregistered.
    function unregisterToken(address baseToken, address savvySwap) external;

    /// @notice Set flow rate of an base token.
    ///
    /// This function reverts if the caller is not the current admin.
    ///
    /// @param baseToken The base token getting the flow rate set.
    /// @param flowRate        The new flow rate.
    function setFlowRate(address baseToken, uint256 flowRate) external;

    /// @notice Sets up a weighting schema.
    ///
    /// @param weightToken The name of the weighting schema.
    /// @param tokens      The yield-tokens to weight.
    /// @param weights     The weights of the yield tokens.
    function setWeights(
        address weightToken,
        address[] memory tokens,
        uint256[] memory weights
    ) external;

    /// @notice Swaps any available flow into the SavvySwap.
    ///
    /// This function is a way for the keeper to force funds to be swapped into the SavvySwap.
    ///
    /// This function will revert if called by any account that is not a keeper. If there is not enough local balance of
    /// `baseToken` held by the SavvySage any additional funds will be withdrawn from the Savvy by
    /// unwrapping `yieldToken`.
    ///
    /// @param baseToken The address of the base token to swap.
    function swap(address baseToken) external;

    /// @notice Flushes funds to the amo.
    ///
    /// @param baseToken The base token to flush.
    /// @param amount          The amount to flush.
    function flushToAmo(address baseToken, uint256 amount) external;

    /// @notice Burns available credit in the savvy.
    function burnCredit() external;

    /// @notice Deposits local collateral into the savvy
    ///
    /// @param baseToken The collateral to deposit.
    /// @param amount          The amount to deposit.
    function depositFunds(address baseToken, uint256 amount) external;

    /// @notice Withdraws collateral from the savvy
    ///
    /// This function reverts if:
    /// - The caller is not the savvySwap.
    /// - There is not enough flow available to fulfill the request.
    /// - There is not enough underlying collateral in the savvy controlled by the buffer to fulfil the request.
    ///
    /// @param baseToken The base token to withdraw.
    /// @param amount          The amount to withdraw.
    /// @param recipient       The account receiving the withdrawn funds.
    function withdraw(
        address baseToken,
        uint256 amount,
        address recipient
    ) external;

    /// @notice Withdraws collateral from the savvy
    ///
    /// @param yieldToken       The yield token to withdraw.
    /// @param shares           The amount of Savvy shares to withdraw.
    /// @param minimumAmountOut The minimum amount of base tokens needed to be recieved as a result of unwrapping the yield tokens.
    function withdrawFromSavvy(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external;
}

