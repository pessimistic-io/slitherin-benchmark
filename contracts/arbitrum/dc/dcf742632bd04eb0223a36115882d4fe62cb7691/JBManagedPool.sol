// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

/**
 * @notice Simple interface to retrieve the version of a deployed contract.
 */
interface IVersion {
    /**
     * @dev Returns a JSON representation of the contract version containing name, version number and task ID.
     */
    function version() external view returns (string memory);
}


/**
 * @notice Interface for ExternalWeightedMath, a contract-wrapper for Weighted Math, Joins and Exits.
 */
interface IExternalWeightedMath {
    /**
     * @dev See `WeightedMath._calculateInvariant`.
     */
    function calculateInvariant(uint256[] memory normalizedWeights, uint256[] memory balances)
        external
        pure
        returns (uint256);

    /**
     * @dev See `WeightedMath._calcOutGivenIn`.
     */
    function calcOutGivenIn(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountIn
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcInGivenOut`.
     */
    function calcInGivenOut(
        uint256 balanceIn,
        uint256 weightIn,
        uint256 balanceOut,
        uint256 weightOut,
        uint256 amountOut
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcBptOutGivenExactTokensIn`.
     */
    function calcBptOutGivenExactTokensIn(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcBptOutGivenExactTokenIn`.
     */
    function calcBptOutGivenExactTokenIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcTokenInGivenExactBptOut`.
     */
    function calcTokenInGivenExactBptOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcAllTokensInGivenExactBptOut`.
     */
    function calcAllTokensInGivenExactBptOut(
        uint256[] memory balances,
        uint256 bptAmountOut,
        uint256 totalBPT
    ) external pure returns (uint256[] memory);

    /**
     * @dev See `WeightedMath._calcBptInGivenExactTokensOut`.
     */
    function calcBptInGivenExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcBptInGivenExactTokenOut`.
     */
    function calcBptInGivenExactTokenOut(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 amountOut,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcTokenOutGivenExactBptIn`.
     */
    function calcTokenOutGivenExactBptIn(
        uint256 balance,
        uint256 normalizedWeight,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 swapFeePercentage
    ) external pure returns (uint256);

    /**
     * @dev See `WeightedMath._calcTokensOutGivenExactBptIn`.
     */
    function calcTokensOutGivenExactBptIn(
        uint256[] memory balances,
        uint256 bptAmountIn,
        uint256 totalBPT
    ) external pure returns (uint256[] memory);

    /**
     * @dev See `WeightedMath._calcBptOutAddToken`.
     */
    function calcBptOutAddToken(uint256 totalSupply, uint256 normalizedWeight) external pure returns (uint256);

    /**
     * @dev See `WeightedJoinsLib.joinExactTokensInForBPTOut`.
     */
    function joinExactTokensInForBPTOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory scalingFactors,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        bytes memory userData
    ) external pure returns (uint256, uint256[] memory);

    /**
     * @dev See `WeightedJoinsLib.joinTokenInForExactBPTOut`.
     */
    function joinTokenInForExactBPTOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        bytes memory userData
    ) external pure returns (uint256, uint256[] memory);

    /**
     * @dev See `WeightedJoinsLib.joinAllTokensInForExactBPTOut`.
     */
    function joinAllTokensInForExactBPTOut(
        uint256[] memory balances,
        uint256 totalSupply,
        bytes memory userData
    ) external pure returns (uint256 bptAmountOut, uint256[] memory amountsIn);

    /**
     * @dev See `WeightedExitsLib.exitExactBPTInForTokenOut`.
     */
    function exitExactBPTInForTokenOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        bytes memory userData
    ) external pure returns (uint256, uint256[] memory);

    /**
     * @dev See `WeightedExitsLib.exitExactBPTInForTokensOut`.
     */
    function exitExactBPTInForTokensOut(
        uint256[] memory balances,
        uint256 totalSupply,
        bytes memory userData
    ) external pure returns (uint256 bptAmountIn, uint256[] memory amountsOut);

    /**
     * @dev See `WeightedExitsLib.exitBPTInForExactTokensOut`.
     */
    function exitBPTInForExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory scalingFactors,
        uint256 totalSupply,
        uint256 swapFeePercentage,
        bytes memory userData
    ) external pure returns (uint256, uint256[] memory);
}



import "./WeightedPoolUserData.sol";
import "./BalancerErrors.sol";
import "./LogExpMath.sol";
import "./FixedPoint.sol";
import "./IERC20.sol";
import "./InputHelpers.sol";


library BasePoolMath {
    using FixedPoint for uint256;

    function computeProportionalAmountsIn(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountOut
    ) internal pure returns (uint256[] memory amountsIn) {
        /************************************************************************************
        // computeProportionalAmountsIn                                                    //
        // (per token)                                                                     //
        // aI = amountIn                   /      bptOut      \                            //
        // b = balance           aI = b * | ----------------- |                            //
        // bptOut = bptAmountOut           \  bptTotalSupply  /                            //
        // bpt = bptTotalSupply                                                            //
        ************************************************************************************/

        // Since we're computing amounts in, we round up overall. This means rounding up on both the
        // multiplication and division.

        uint256 bptRatio = bptAmountOut.divUp(bptTotalSupply);

        amountsIn = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsIn[i] = balances[i].mulUp(bptRatio);
        }
    }

    function computeProportionalAmountsOut(
        uint256[] memory balances,
        uint256 bptTotalSupply,
        uint256 bptAmountIn
    ) internal pure returns (uint256[] memory amountsOut) {
        /**********************************************************************************************
        // computeProportionalAmountsOut                                                             //
        // (per token)                                                                               //
        // aO = tokenAmountOut             /        bptIn         \                                  //
        // b = tokenBalance      a0 = b * | ---------------------  |                                 //
        // bptIn = bptAmountIn             \     bptTotalSupply    /                                 //
        // bpt = bptTotalSupply                                                                      //
        **********************************************************************************************/

        // Since we're computing an amount out, we round down overall. This means rounding down on both the
        // multiplication and division.

        uint256 bptRatio = bptAmountIn.divDown(bptTotalSupply);

        amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsOut[i] = balances[i].mulDown(bptRatio);
        }
    }
}

library ComposablePoolLib {
    using FixedPoint for uint256;

    /**
     * @notice Returns a slice of the original array, with the BPT token address removed.
     * @dev *This mutates the original array*, which should not be used anymore after calling this function.
     * It's recommended to call this function such that the calling function either immediately returns or overwrites
     * the original array variable so it cannot be accessed.
     */
    function dropBptFromTokens(IERC20[] memory registeredTokens) internal pure returns (IERC20[] memory tokens) {
        assembly {
            // An array's memory representation is a 32 byte word for the length followed by 32 byte words for
            // each element, with the stack variable pointing to the length. Since there's no memory deallocation,
            // and we are free to mutate the received array, the cheapest way to remove the first element is to
            // create a new subarray by overwriting the first element with a reduced length, and moving the pointer
            // forward to that position.
            //
            // Original:
            // [ length ] [ data[0] ] [ data[1] ] [ ... ]
            // ^ pointer
            //
            // Modified:
            // [ length ] [ length - 1 ] [ data[1] ] [ ... ]
            //                ^ pointer
            //
            // Note that this can only be done if the element to remove is the first one, which is one of the reasons
            // why Composable Pools register BPT as the first token.
            mstore(add(registeredTokens, 32), sub(mload(registeredTokens), 1))
            tokens := add(registeredTokens, 32)
        }
    }

    /**
     * @notice Returns the virtual supply, and a slice of the original balances array with the BPT balance removed.
     * @dev *This mutates the original array*, which should not be used anymore after calling this function.
     * It's recommended to call this function such that the calling function either immediately returns or overwrites
     * the original array variable so it cannot be accessed.
     */
    function dropBptFromBalances(uint256 totalSupply, uint256[] memory registeredBalances)
        internal
        pure
        returns (uint256 virtualSupply, uint256[] memory balances)
    {
        virtualSupply = totalSupply.sub(registeredBalances[0]);
        assembly {
            // See dropBptFromTokens for a detailed explanation of how this works.
            mstore(add(registeredBalances, 32), sub(mload(registeredBalances), 1))
            balances := add(registeredBalances, 32)
        }
    }

    /**
     * @notice Returns slices of the original arrays, with the BPT token address and balance removed.
     * @dev *This mutates the original arrays*, which should not be used anymore after calling this function.
     * It's recommended to call this function such that the calling function either immediately returns or overwrites
     * the original array variable so it cannot be accessed.
     */
    function dropBpt(IERC20[] memory registeredTokens, uint256[] memory registeredBalances)
        internal
        pure
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        assembly {
            // See dropBptFromTokens for a detailed explanation of how this works
            mstore(add(registeredTokens, 32), sub(mload(registeredTokens), 1))
            tokens := add(registeredTokens, 32)

            mstore(add(registeredBalances, 32), sub(mload(registeredBalances), 1))
            balances := add(registeredBalances, 32)
        }
    }

    /**
     * @notice Returns the passed array prepended with a zero element.
     */
    function prependZeroElement(uint256[] memory array) internal pure returns (uint256[] memory prependedArray) {
        prependedArray = new uint256[](array.length + 1);
        for (uint256 i = 0; i < array.length; i++) {
            prependedArray[i + 1] = array[i];
        }
    }
}

import "./IAuthentication.sol";
import "./IAuthorizer.sol";
import "./PoolRegistrationLib.sol";
import "./IVault.sol";


interface IPoolSwapStructs {
    // This is not really an interface - it just defines common structs used by other interfaces: IGeneralPool and
    // IMinimalSwapInfoPool.
    //
    // This data structure represents a request for a token swap, where `kind` indicates the swap type ('given in' or
    // 'given out') which indicates whether or not the amount sent by the pool is known.
    //
    // The pool receives `tokenIn` and sends `tokenOut`. `amount` is the number of `tokenIn` tokens the pool will take
    // in, or the number of `tokenOut` tokens the Pool will send out, depending on the given swap `kind`.
    //
    // All other fields are not strictly necessary for most swaps, but are provided to support advanced scenarios in
    // some Pools.
    //
    // `poolId` is the ID of the Pool involved in the swap - this is useful for Pool contracts that implement more than
    // one Pool.
    //
    // The meaning of `lastChangeBlock` depends on the Pool specialization:
    //  - Two Token or Minimal Swap Info: the last block in which either `tokenIn` or `tokenOut` changed its total
    //    balance.
    //  - General: the last block in which *any* of the Pool's registered tokens changed its total balance.
    //
    // `from` is the origin address for the funds the Pool receives, and `to` is the destination address
    // where the Pool sends the outgoing tokens.
    //
    // `userData` is extra data provided by the caller - typically a signature from a trusted party.
    struct SwapRequest {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amount;
        // Misc data
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }
}

/**
 * @dev Interface for adding and removing liquidity that all Pool contracts should implement. Note that this is not
 * the complete Pool contract interface, as it is missing the swap hooks. Pool contracts should also inherit from
 * either IGeneralPool or IMinimalSwapInfoPool
 */
interface IBasePool is IPoolSwapStructs {
    /**
     * @dev Called by the Vault when a user calls `IVault.joinPool` to add liquidity to this Pool. Returns how many of
     * each registered token the user should provide, as well as the amount of protocol fees the Pool owes to the Vault.
     * The Vault will then take tokens from `sender` and add them to the Pool's balances, as well as collect
     * the reported amount in protocol fees, which the pool should calculate based on `protocolSwapFeePercentage`.
     *
     * Protocol fees are reported and charged on join events so that the Pool is free of debt whenever new users join.
     *
     * `sender` is the account performing the join (from which tokens will be withdrawn), and `recipient` is the account
     * designated to receive any benefits (typically pool shares). `balances` contains the total balances
     * for each token the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
     *
     * `lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
     * balance.
     *
     * `userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
     * join (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
     *
     * Contracts implementing this function should check that the caller is indeed the Vault before performing any
     * state-changing operations, such as minting pool shares.
     */
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts);

    /**
     * @dev Called by the Vault when a user calls `IVault.exitPool` to remove liquidity from this Pool. Returns how many
     * tokens the Vault should deduct from the Pool's balances, as well as the amount of protocol fees the Pool owes
     * to the Vault. The Vault will then take tokens from the Pool's balances and send them to `recipient`,
     * as well as collect the reported amount in protocol fees, which the Pool should calculate based on
     * `protocolSwapFeePercentage`.
     *
     * Protocol fees are charged on exit events to guarantee that users exiting the Pool have paid their share.
     *
     * `sender` is the account performing the exit (typically the pool shareholder), and `recipient` is the account
     * to which the Vault will send the proceeds. `balances` contains the total token balances for each token
     * the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
     *
     * `lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
     * balance.
     *
     * `userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
     * exit (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
     *
     * Contracts implementing this function should check that the caller is indeed the Vault before performing any
     * state-changing operations, such as burning pool shares.
     */
    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts);

    /**
     * @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
     */
    function getPoolId() external view returns (bytes32);

    /**
     * @dev Returns the current swap fee percentage as a 18 decimal fixed point number, so e.g. 1e17 corresponds to a
     * 10% swap fee.
     */
    function getSwapFeePercentage() external view returns (uint256);

    /**
     * @dev Returns the scaling factors of each of the Pool's tokens. This is an implementation detail that is typically
     * not relevant for outside parties, but which might be useful for some types of Pools.
     */
    function getScalingFactors() external view returns (uint256[] memory);

    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptOut, uint256[] memory amountsIn);

    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}

interface IManagedPool is IBasePool {
    event GradualSwapFeeUpdateScheduled(
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    );
    event GradualWeightUpdateScheduled(
        uint256 startTime,
        uint256 endTime,
        uint256[] startWeights,
        uint256[] endWeights
    );
    event SwapEnabledSet(bool swapEnabled);
    event JoinExitEnabledSet(bool joinExitEnabled);
    event MustAllowlistLPsSet(bool mustAllowlistLPs);
    event AllowlistAddressAdded(address indexed member);
    event AllowlistAddressRemoved(address indexed member);
    event ManagementAumFeePercentageChanged(uint256 managementAumFeePercentage);
    event ManagementAumFeeCollected(uint256 bptAmount);
    event CircuitBreakerSet(
        IERC20 indexed token,
        uint256 bptPrice,
        uint256 lowerBoundPercentage,
        uint256 upperBoundPercentage
    );
    event TokenAdded(IERC20 indexed token, uint256 normalizedWeight);
    event TokenRemoved(IERC20 indexed token);

    /**
     * @notice Returns the effective BPT supply.
     *
     * @dev The Pool owes debt to the Protocol and the Pool's owner in the form of unminted BPT, which will be minted
     * immediately before the next join or exit. We need to take these into account since, even if they don't yet exist,
     * they will effectively be included in any Pool operation that involves BPT.
     *
     * In the vast majority of cases, this function should be used instead of `totalSupply()`.
     */
    function getActualSupply() external view returns (uint256);

    // Swap fee percentage

    /**
     * @notice Schedule a gradual swap fee update.
     * @dev The swap fee will change from the given starting value (which may or may not be the current
     * value) to the given ending fee percentage, over startTime to endTime.
     *
     * Note that calling this with a starting swap fee different from the current value will immediately change the
     * current swap fee to `startSwapFeePercentage`, before commencing the gradual change at `startTime`.
     * Emits the GradualSwapFeeUpdateScheduled event.
     * This is a permissioned function.
     *
     * @param startTime - The timestamp when the swap fee change will begin.
     * @param endTime - The timestamp when the swap fee change will end (must be >= startTime).
     * @param startSwapFeePercentage - The starting value for the swap fee change.
     * @param endSwapFeePercentage - The ending value for the swap fee change. If the current timestamp >= endTime,
     * `getSwapFeePercentage()` will return this value.
     */
    function updateSwapFeeGradually(
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    ) external;

    /**
     * @notice Returns the current gradual swap fee update parameters.
     * @dev The current swap fee can be retrieved via `getSwapFeePercentage()`.
     * @return startTime - The timestamp when the swap fee update will begin.
     * @return endTime - The timestamp when the swap fee update will end.
     * @return startSwapFeePercentage - The starting swap fee percentage (could be different from the current value).
     * @return endSwapFeePercentage - The final swap fee percentage, when the current timestamp >= endTime.
     */
    function getGradualSwapFeeUpdateParams()
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 startSwapFeePercentage,
            uint256 endSwapFeePercentage
        );

    // Token weights

    /**
     * @notice Schedule a gradual weight change.
     * @dev The weights will change from their current values to the given endWeights, over startTime to endTime.
     * This is a permissioned function.
     *
     * Since, unlike with swap fee updates, we generally do not want to allow instantaneous weight changes,
     * the weights always start from their current values. This also guarantees a smooth transition when
     * updateWeightsGradually is called during an ongoing weight change.
     * @param startTime - The timestamp when the weight change will begin.
     * @param endTime - The timestamp when the weight change will end (can be >= startTime).
     * @param tokens - The tokens associated with the target weights (must match the current pool tokens).
     * @param endWeights - The target weights. If the current timestamp >= endTime, `getNormalizedWeights()`
     * will return these values.
     */
    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        IERC20[] memory tokens,
        uint256[] memory endWeights
    ) external;

    /**
     * @notice Returns all normalized weights, in the same order as the Pool's tokens.
     */
    function getNormalizedWeights() external view returns (uint256[] memory);

    /**
     * @notice Returns the current gradual weight change update parameters.
     * @dev The current weights can be retrieved via `getNormalizedWeights()`.
     * @return startTime - The timestamp when the weight update will begin.
     * @return endTime - The timestamp when the weight update will end.
     * @return startWeights - The starting weights, when the weight change was initiated.
     * @return endWeights - The final weights, when the current timestamp >= endTime.
     */
    function getGradualWeightUpdateParams()
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256[] memory startWeights,
            uint256[] memory endWeights
        );

    // Join and Exit enable/disable

    /**
     * @notice Enable or disable joins and exits. Note that this does not affect Recovery Mode exits.
     * @dev Emits the JoinExitEnabledSet event. This is a permissioned function.
     * @param joinExitEnabled - The new value of the join/exit enabled flag.
     */
    function setJoinExitEnabled(bool joinExitEnabled) external;

    /**
     * @notice Returns whether joins and exits are enabled.
     */
    function getJoinExitEnabled() external view returns (bool);

    // Swap enable/disable

    /**
     * @notice Enable or disable trading.
     * @dev Emits the SwapEnabledSet event. This is a permissioned function.
     * @param swapEnabled - The new value of the swap enabled flag.
     */
    function setSwapEnabled(bool swapEnabled) external;

    /**
     * @notice Returns whether swaps are enabled.
     */
    function getSwapEnabled() external view returns (bool);

    // LP Allowlist

    /**
     * @notice Enable or disable the LP allowlist.
     * @dev Note that any addresses added to the allowlist will be retained if the allowlist is toggled off and
     * back on again, because this action does not affect the list of LP addresses.
     * Emits the MustAllowlistLPsSet event. This is a permissioned function.
     * @param mustAllowlistLPs - The new value of the mustAllowlistLPs flag.
     */
    function setMustAllowlistLPs(bool mustAllowlistLPs) external;

    /**
     * @notice Adds an address to the LP allowlist.
     * @dev Will fail if the address is already allowlisted.
     * Emits the AllowlistAddressAdded event. This is a permissioned function.
     * @param member - The address to be added to the allowlist.
     */
    function addAllowedAddress(address member) external;

    /**
     * @notice Removes an address from the LP allowlist.
     * @dev Will fail if the address was not previously allowlisted.
     * Emits the AllowlistAddressRemoved event. This is a permissioned function.
     * @param member - The address to be removed from the allowlist.
     */
    function removeAllowedAddress(address member) external;

    /**
     * @notice Returns whether the allowlist for LPs is enabled.
     */
    function getMustAllowlistLPs() external view returns (bool);

    /**
     * @notice Check whether an LP address is on the allowlist.
     * @dev This simply checks the list, regardless of whether the allowlist feature is enabled.
     * @param member - The address to check against the allowlist.
     * @return true if the given address is on the allowlist.
     */
    function isAddressOnAllowlist(address member) external view returns (bool);

    // Management fees

    /**
     * @notice Collect any accrued AUM fees and send them to the pool manager.
     * @dev This can be called by anyone to collect accrued AUM fees - and will be called automatically
     * whenever the supply changes (e.g., joins and exits, add and remove token), and before the fee
     * percentage is changed by the manager, to prevent fees from being applied retroactively.
     * @return The amount of BPT minted to the manager.
     */
    function collectAumManagementFees() external returns (uint256);

    /**
     * @notice Setter for the yearly percentage AUM management fee, which is payable to the pool manager.
     * @dev Attempting to collect AUM fees in excess of the maximum permitted percentage will revert.
     * To avoid retroactive fee increases, we force collection at the current fee percentage before processing
     * the update. Emits the ManagementAumFeePercentageChanged event. This is a permissioned function.
     * @param managementAumFeePercentage - The new management AUM fee percentage.
     * @return amount - The amount of BPT minted to the manager before the update, if any.
     */
    function setManagementAumFeePercentage(uint256 managementAumFeePercentage) external returns (uint256);

    /**
     * @notice Returns the management AUM fee percentage as an 18-decimal fixed point number and the timestamp of the
     * last collection of AUM fees.
     */
    function getManagementAumFeeParams()
        external
        view
        returns (uint256 aumFeePercentage, uint256 lastCollectionTimestamp);

    // Circuit Breakers

    /**
     * @notice Set a circuit breaker for one or more tokens.
     * @dev This is a permissioned function. The lower and upper bounds are percentages, corresponding to a
     * relative change in the token's spot price: e.g., a lower bound of 0.8 means the breaker should prevent
     * trades that result in the value of the token dropping 20% or more relative to the rest of the pool.
     */
    function setCircuitBreakers(
        IERC20[] memory tokens,
        uint256[] memory bptPrices,
        uint256[] memory lowerBoundPercentages,
        uint256[] memory upperBoundPercentages
    ) external;

    /**
     * @notice Return the full circuit breaker state for the given token.
     * @dev These are the reference values (BPT price and reference weight) passed in when the breaker was set,
     * along with the percentage bounds. It also returns the current BPT price bounds, needed to check whether
     * the circuit breaker should trip.
     */
    function getCircuitBreakerState(IERC20 token)
        external
        view
        returns (
            uint256 bptPrice,
            uint256 referenceWeight,
            uint256 lowerBound,
            uint256 upperBound,
            uint256 lowerBptPriceBound,
            uint256 upperBptPriceBound
        );

    // Add/remove tokens

    /**
     * @notice Adds a token to the Pool's list of tradeable tokens. This is a permissioned function.
     *
     * @dev By adding a token to the Pool's composition, the weights of all other tokens will be decreased. The new
     * token will have no balance - it is up to the owner to provide some immediately after calling this function.
     * Note however that regular join functions will not work while the new token has no balance: the only way to
     * deposit an initial amount is by using an Asset Manager.
     *
     * Token addition is forbidden during a weight change, or if one is scheduled to happen in the future.
     *
     * The caller may additionally pass a non-zero `mintAmount` to have some BPT be minted for them, which might be
     * useful in some scenarios to account for the fact that the Pool will have more tokens.
     *
     * Emits the TokenAdded event.
     *
     * @param tokenToAdd - The ERC20 token to be added to the Pool.
     * @param assetManager - The Asset Manager for the token.
     * @param tokenToAddNormalizedWeight - The normalized weight of `token` relative to the other tokens in the Pool.
     * @param mintAmount - The amount of BPT to be minted as a result of adding `token` to the Pool.
     * @param recipient - The address to receive the BPT minted by the Pool.
     */
    function addToken(
        IERC20 tokenToAdd,
        address assetManager,
        uint256 tokenToAddNormalizedWeight,
        uint256 mintAmount,
        address recipient
    ) external;

    /**
     * @notice Removes a token from the Pool's list of tradeable tokens.
     * @dev Tokens can only be removed if the Pool has more than 2 tokens, as it can never have fewer than 2 (not
     * including BPT). Token removal is also forbidden during a weight change, or if one is scheduled to happen in
     * the future.
     *
     * Emits the TokenRemoved event. This is a permissioned function.
     *
     * The caller may additionally pass a non-zero `burnAmount` to burn some of their BPT, which might be useful
     * in some scenarios to account for the fact that the Pool now has fewer tokens. This is a permissioned function.
     * @param tokenToRemove - The ERC20 token to be removed from the Pool.
     * @param burnAmount - The amount of BPT to be burned after removing `token` from the Pool.
     * @param sender - The address to burn BPT from.
     */
    function removeToken(
        IERC20 tokenToRemove,
        uint256 burnAmount,
        address sender
    ) external;
}



/**
 * @dev Source of truth for all Protocol Fee percentages, that is, how much the protocol charges certain actions. Some
 * of these values may also be retrievable from other places (such as the swap fee percentage), but this is the
 * preferred source nonetheless.
 */
interface IProtocolFeePercentagesProvider {
    // All fee percentages are 18-decimal fixed point numbers, so e.g. 1e18 = 100% and 1e16 = 1%.

    // Emitted when a new fee type is registered.
    event ProtocolFeeTypeRegistered(uint256 indexed feeType, string name, uint256 maximumPercentage);

    // Emitted when the value of a fee type changes.
    // IMPORTANT: it is possible for a third party to modify the SWAP and FLASH_LOAN fee type values directly in the
    // ProtocolFeesCollector, which will result in this event not being emitted despite their value changing. Such usage
    // of the ProtocolFeesCollector is however discouraged: all state-changing interactions with it should originate in
    // this contract.
    event ProtocolFeePercentageChanged(uint256 indexed feeType, uint256 percentage);

    /**
     * @dev Registers a new fee type in the system, making it queryable via `getFeeTypePercentage` and `getFeeTypeName`,
     * as well as configurable via `setFeeTypePercentage`.
     *
     * `feeType` can be any arbitrary value (that is not in use).
     *
     * It is not possible to de-register fee types, nor change their name or maximum value.
     */
    function registerFeeType(
        uint256 feeType,
        string memory name,
        uint256 maximumValue,
        uint256 initialValue
    ) external;

    /**
     * @dev Returns true if `feeType` has been registered and can be queried.
     */
    function isValidFeeType(uint256 feeType) external view returns (bool);

    /**
     * @dev Returns true if `value` is a valid percentage value for `feeType`.
     */
    function isValidFeeTypePercentage(uint256 feeType, uint256 value) external view returns (bool);

    /**
     * @dev Sets the percentage value for `feeType` to `newValue`.
     *
     * IMPORTANT: it is possible for a third party to modify the SWAP and FLASH_LOAN fee type values directly in the
     * ProtocolFeesCollector, without invoking this function. This will result in the `ProtocolFeePercentageChanged`
     * event not being emitted despite their value changing. Such usage of the ProtocolFeesCollector is however
     * discouraged: only this contract should be granted permission to call `setSwapFeePercentage` and
     * `setFlashLoanFeePercentage`.
     */
    function setFeeTypePercentage(uint256 feeType, uint256 newValue) external;

    /**
     * @dev Returns the current percentage value for `feeType`. This is the preferred mechanism for querying these -
     * whenever possible, use this fucntion instead of e.g. querying the ProtocolFeesCollector.
     */
    function getFeeTypePercentage(uint256 feeType) external view returns (uint256);

    /**
     * @dev Returns `feeType`'s maximum value.
     */
    function getFeeTypeMaximumPercentage(uint256 feeType) external view returns (uint256);

    /**
     * @dev Returns `feeType`'s name.
     */
    function getFeeTypeName(uint256 feeType) external view returns (string memory);
}

library ProtocolFeeType {
    // This list is not exhaustive - more fee types can be added to the system. It is expected for this list to be
    // extended with new fee types as they are registered, to keep them all in one place and reduce
    // likelihood of user error.

    // solhint-disable private-vars-leading-underscore
    uint256 internal constant SWAP = 0;
    uint256 internal constant FLASH_LOAN = 1;
    uint256 internal constant YIELD = 2;
    uint256 internal constant AUM = 3;
    // solhint-enable private-vars-leading-underscore
}

// solhint-disable

function _asIAsset(IERC20[] memory tokens) pure returns (IAsset[] memory assets) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
        assets := tokens
    }
}

function _sortTokens(
    IERC20 tokenA,
    IERC20 tokenB
) pure returns (IERC20[] memory tokens) {
    bool aFirst = tokenA < tokenB;
    IERC20[] memory sortedTokens = new IERC20[](2);

    sortedTokens[0] = aFirst ? tokenA : tokenB;
    sortedTokens[1] = aFirst ? tokenB : tokenA;

    return sortedTokens;
}

function _insertSorted(IERC20[] memory tokens, IERC20 token) pure returns (IERC20[] memory sorted) {
    sorted = new IERC20[](tokens.length + 1);

    if (tokens.length == 0) {
        sorted[0] = token;
        return sorted;
    }

    uint256 i;
    for (i = tokens.length; i > 0 && tokens[i - 1] > token; i--) sorted[i] = tokens[i - 1];
    for (uint256 j = 0; j < i; j++) sorted[j] = tokens[j];
    sorted[i] = token;
}

function _findTokenIndex(IERC20[] memory tokens, IERC20 token) pure returns (uint256) {
    // Note that while we know tokens are initially sorted, we cannot assume this will hold throughout
    // the pool's lifetime, as pools with mutable tokens can append and remove tokens in any order.
    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
        if (tokens[i] == token) {
            return i;
        }
    }

    _revert(Errors.INVALID_TOKEN);
}

import "./Math.sol";



// solhint-disable

// To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had 18 decimals.
// e.g. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be represented as 1e18,
// whereas without scaling 1 USDC would be represented as 1e6.
// This allows us to not consider differences in token decimals in the internal Pool maths, simplifying it greatly.

// Single Value

/**
 * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
 * scaling or not.
 */
function _upscale(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    // Upscale rounding wouldn't necessarily always go in the same direction: in a swap for example the balance of
    // token in should be rounded up, and that of token out rounded down. This is the only place where we round in
    // the same direction for all amounts, as the impact of this rounding is expected to be minimal.
    return FixedPoint.mulDown(amount, scalingFactor);
}

/**
 * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
 * whether it needed scaling or not. The result is rounded down.
 */
function _downscaleDown(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    return FixedPoint.divDown(amount, scalingFactor);
}

/**
 * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
 * whether it needed scaling or not. The result is rounded up.
 */
function _downscaleUp(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    return FixedPoint.divUp(amount, scalingFactor);
}

// Array

/**
 * @dev Same as `_upscale`, but for an entire array. This function does not return anything, but instead *mutates*
 * the `amounts` array.
 */
function _upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) pure {
    uint256 length = amounts.length;
    InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

    for (uint256 i = 0; i < length; ++i) {
        amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
    }
}

/**
 * @dev Same as `_downscaleDown`, but for an entire array. This function does not return anything, but instead
 * *mutates* the `amounts` array.
 */
function _downscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) pure {
    uint256 length = amounts.length;
    InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

    for (uint256 i = 0; i < length; ++i) {
        amounts[i] = FixedPoint.divDown(amounts[i], scalingFactors[i]);
    }
}

/**
 * @dev Same as `_downscaleUp`, but for an entire array. This function does not return anything, but instead
 * *mutates* the `amounts` array.
 */
function _downscaleUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) pure {
    uint256 length = amounts.length;
    InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

    for (uint256 i = 0; i < length; ++i) {
        amounts[i] = FixedPoint.divUp(amounts[i], scalingFactors[i]);
    }
}

function _computeScalingFactor(IERC20 token) view returns (uint256) {
    // Tokens that don't implement the `decimals` method are not supported.
    uint256 tokenDecimals = ERC20(address(token)).decimals();

    // Tokens with more than 18 decimals are not supported.
    uint256 decimalsDifference = Math.sub(18, tokenDecimals);
    return FixedPoint.ONE * 10**decimalsDifference;
}

import "./WordCodec.sol";

library ExternalFees {
    using FixedPoint for uint256;

    /**
     * @dev Calculates the amount of BPT necessary to give ownership of a given percentage of the Pool to an external
     * third party. In the case of protocol fees, this is the DAO, but could also be a pool manager, etc.
     * Note that this function reverts if `poolPercentage` >= 100%, it's expected that the caller will enforce this.
     * @param totalSupply - The total supply of the pool prior to minting BPT.
     * @param poolOwnershipPercentage - The desired ownership percentage of the pool to have as a result of minting BPT.
     * @return bptAmount - The amount of BPT to mint such that it is `poolPercentage` of the resultant total supply.
     */
    function bptForPoolOwnershipPercentage(uint256 totalSupply, uint256 poolOwnershipPercentage)
        internal
        pure
        returns (uint256)
    {
        // If we mint some amount `bptAmount` of BPT then the percentage ownership of the pool this grants is given by:
        // `poolOwnershipPercentage = bptAmount / (totalSupply + bptAmount)`.
        // Solving for `bptAmount`, we arrive at:
        // `bptAmount = totalSupply * poolOwnershipPercentage / (1 - poolOwnershipPercentage)`.
        return Math.divDown(Math.mul(totalSupply, poolOwnershipPercentage), poolOwnershipPercentage.complement());
    }
}

library InvariantGrowthProtocolSwapFees {
    using FixedPoint for uint256;

    function getProtocolOwnershipPercentage(
        uint256 invariantGrowthRatio,
        uint256 supplyGrowthRatio,
        uint256 protocolSwapFeePercentage
    ) internal pure returns (uint256) {
        // Joins and exits are symmetrical; for simplicity, we consider a join, where the invariant and supply
        // both increase.

        // |-------------------------|-- original invariant * invariantGrowthRatio
        // |   increase from fees    |
        // |-------------------------|-- original invariant * supply growth ratio (fee-less invariant)
        // |                         |
        // | increase from balances  |
        // |-------------------------|-- original invariant
        // |                         |
        // |                         |  |------------------|-- currentSupply
        // |                         |  |    BPT minted    |
        // |                         |  |------------------|-- previousSupply
        // |   original invariant    |  |  original supply |
        // |_________________________|  |__________________|
        //
        // If the join is proportional, the invariant and supply will likewise increase proportionally,
        // so the growth ratios (invariantGrowthRatio / supplyGrowthRatio) will be equal. In this case, we do not charge
        // any protocol fees.
        // We also charge no protocol fees in the case where `invariantGrowthRatio < supplyGrowthRatio` to avoid
        // potential underflows, however this should only occur in extremely low volume actions due solely to rounding
        // error.

        if ((supplyGrowthRatio >= invariantGrowthRatio) || (protocolSwapFeePercentage == 0)) return 0;

        // If the join is non-proportional, the supply increase will be proportionally less than the invariant increase,
        // since the BPT minted will be based on fewer tokens (because swap fees are not included). So the supply growth
        // is due entirely to the balance changes, while the invariant growth also includes swap fees.
        //
        // To isolate the amount of increase by fees then, we multiply the original invariant by the supply growth
        // ratio to get the "feeless invariant". The difference between the final invariant and this value is then
        // the amount of the invariant due to fees, which we convert to a percentage by normalizing against the
        // final invariant. This is expressed as the expression below:
        //
        // invariantGrowthFromFees = currentInvariant - supplyGrowthRatio * previousInvariant
        //
        // We then divide through by current invariant so the LHS can be identified as the fraction of the pool which
        // is made up of accumulated swap fees.
        //
        // swapFeesPercentage = 1 - supplyGrowthRatio * previousInvariant / currentInvariant
        //
        // We then define `invariantGrowthRatio` in a similar fashion to `supplyGrowthRatio` to give the result:
        //
        // swapFeesPercentage = 1 - supplyGrowthRatio / invariantGrowthRatio
        //
        // Using this form allows us to consider only the ratios of the two invariants, rather than their absolute
        // values: a useful property, as this is sometimes easier than calculating the full invariant twice.

        // We've already checked that `supplyGrowthRatio` is smaller than `invariantGrowthRatio`, and hence their ratio
        // smaller than FixedPoint.ONE, allowing for unchecked arithmetic.
        uint256 swapFeesPercentage = FixedPoint.ONE - supplyGrowthRatio.divDown(invariantGrowthRatio);

        // We then multiply by the protocol swap fee percentage to get the fraction of the pool which the protocol
        // should own once fees have been collected.
        return swapFeesPercentage.mulDown(protocolSwapFeePercentage);
    }

    function calcDueProtocolFees(
        uint256 invariantGrowthRatio,
        uint256 previousSupply,
        uint256 currentSupply,
        uint256 protocolSwapFeePercentage
    ) internal pure returns (uint256) {
        uint256 protocolOwnershipPercentage = getProtocolOwnershipPercentage(
            invariantGrowthRatio,
            currentSupply.divDown(previousSupply),
            protocolSwapFeePercentage
        );

        return ExternalFees.bptForPoolOwnershipPercentage(currentSupply, protocolOwnershipPercentage);
    }
}



/**
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCast {
    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        _require(value >> 255 == 0, Errors.SAFE_CAST_VALUE_CANT_FIT_INT256);
        return int256(value);
    }

    /**
     * @dev Converts an unsigned uint256 into an unsigned uint64.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxUint64.
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        _require(value <= type(uint64).max, Errors.SAFE_CAST_VALUE_CANT_FIT_UINT64);
        return uint64(value);
    }
}





library BasePoolUserData {
    // Special ExitKind for all pools, used in Recovery Mode. Use the max 8-bit value to prevent conflicts
    // with future additions to the ExitKind enums (or any front-end code that maps to existing values)
    uint8 public constant RECOVERY_MODE_EXIT_KIND = 255;

    // Return true if this is the special exit kind.
    function isRecoveryModeExitKind(bytes memory self) internal pure returns (bool) {
        // Check for the "no data" case, or abi.decode would revert
        return self.length > 0 && abi.decode(self, (uint8)) == RECOVERY_MODE_EXIT_KIND;
    }

    // Parse the bptAmountIn out of the userData
    function recoveryModeExit(bytes memory self) internal pure returns (uint256 bptAmountIn) {
        (, bptAmountIn) = abi.decode(self, (uint8, uint256));
    }
}



/**
 * @dev Interface for the RecoveryMode module.
 */
interface IRecoveryMode {
    /**
     * @dev Emitted when the Recovery Mode status changes.
     */
    event RecoveryModeStateChanged(bool enabled);

    /**
     * @notice Enables Recovery Mode in the Pool, disabling protocol fee collection and allowing for safe proportional
     * exits with low computational complexity and no dependencies.
     */
    function enableRecoveryMode() external;

    /**
     * @notice Disables Recovery Mode in the Pool, restoring protocol fee collection and disallowing proportional exits.
     */
    function disableRecoveryMode() external;

    /**
     * @notice Returns true if the Pool is in Recovery Mode.
     */
    function inRecoveryMode() external view returns (bool);
}

/**
 * @dev Building block for performing access control on external functions.
 *
 * This contract is used via the `authenticate` modifier (or the `_authenticateCaller` function), which can be applied
 * to external functions to only make them callable by authorized accounts.
 *
 * Derived contracts must implement the `_canPerform` function, which holds the actual access control logic.
 */
abstract contract Authentication is IAuthentication {
    bytes32 private immutable _actionIdDisambiguator;

    /**
     * @dev The main purpose of the `actionIdDisambiguator` is to prevent accidental function selector collisions in
     * multi contract systems.
     *
     * There are two main uses for it:
     *  - if the contract is a singleton, any unique identifier can be used to make the associated action identifiers
     *    unique. The contract's own address is a good option.
     *  - if the contract belongs to a family that shares action identifiers for the same functions, an identifier
     *    shared by the entire family (and no other contract) should be used instead.
     */
    constructor(bytes32 actionIdDisambiguator) {
        _actionIdDisambiguator = actionIdDisambiguator;
    }

    /**
     * @dev Reverts unless the caller is allowed to call this function. Should only be applied to external functions.
     */
    modifier authenticate() {
        _authenticateCaller();
        _;
    }

    /**
     * @dev Reverts unless the caller is allowed to call the entry point function.
     */
    function _authenticateCaller() internal view {
        bytes32 actionId = getActionId(msg.sig);
        _require(_canPerform(actionId, msg.sender), Errors.SENDER_NOT_ALLOWED);
    }

    function getActionId(bytes4 selector) public view override returns (bytes32) {
        // Each external function is dynamically assigned an action identifier as the hash of the disambiguator and the
        // function selector. Disambiguation is necessary to avoid potential collisions in the function selectors of
        // multiple contracts.
        return keccak256(abi.encodePacked(_actionIdDisambiguator, selector));
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual returns (bool);
}

/**
 * @dev Base authorization layer implementation for Pools.
 *
 * The owner account can call some of the permissioned functions - access control of the rest is delegated to the
 * Authorizer. Note that this owner is immutable: more sophisticated permission schemes, such as multiple ownership,
 * granular roles, etc., could be built on top of this by making the owner a smart contract.
 *
 * Access control of all other permissioned functions is delegated to an Authorizer. It is also possible to delegate
 * control of *all* permissioned functions to the Authorizer by setting the owner address to `_DELEGATE_OWNER`.
 */
abstract contract BasePoolAuthorization is Authentication {
    address private immutable _owner;

    address internal constant _DELEGATE_OWNER = 0xBA1BA1ba1BA1bA1bA1Ba1BA1ba1BA1bA1ba1ba1B;

    constructor(address owner) {
        _owner = owner;
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function getAuthorizer() external view returns (IAuthorizer) {
        return _getAuthorizer();
    }

    function _canPerform(bytes32 actionId, address account) internal view override returns (bool) {
        if ((getOwner() != _DELEGATE_OWNER) && _isOwnerOnlyAction(actionId)) {
            // Only the owner can perform "owner only" actions, unless the owner is delegated.
            return msg.sender == getOwner();
        } else {
            // Non-owner actions are always processed via the Authorizer, as "owner only" ones are when delegated.
            return _getAuthorizer().canPerform(actionId, account, address(this));
        }
    }

    function _isOwnerOnlyAction(bytes32) internal view virtual returns (bool) {
        return false;
    }

    function _getAuthorizer() internal view virtual returns (IAuthorizer);
}

/**
 * @notice Handle storage and state changes for pools that support "Recovery Mode".
 *
 * @dev This is intended to provide a safe way to exit any pool during some kind of emergency, to avoid locking funds
 * in the event the pool enters a non-functional state (i.e., some code that normally runs during exits is causing
 * them to revert).
 *
 * Recovery Mode is *not* the same as pausing the pool. The pause function is only available during a short window
 * after factory deployment. Pausing can only be intentionally reversed during a buffer period, and the contract
 * will permanently unpause itself thereafter. Paused pools are completely disabled, in a kind of suspended animation,
 * until they are voluntarily or involuntarily unpaused.
 *
 * By contrast, a privileged account - typically a governance multisig - can place a pool in Recovery Mode at any
 * time, and it is always reversible. The pool is *not* disabled while in this mode: though of course whatever
 * condition prompted the transition to Recovery Mode has likely effectively disabled some functions. Rather,
 * a special "clean" exit is enabled, which runs the absolute minimum code necessary to exit proportionally.
 * In particular, stable pools do not attempt to compute the invariant (which is a complex, iterative calculation
 * that can fail in extreme circumstances), and no protocol fees are collected.
 *
 * It is critical to ensure that turning on Recovery Mode would do no harm, if activated maliciously or in error.
 */
abstract contract RecoveryMode is IRecoveryMode, BasePoolAuthorization {
    using FixedPoint for uint256;
    using BasePoolUserData for bytes;

    /**
     * @dev Reverts if the contract is in Recovery Mode.
     */
    modifier whenNotInRecoveryMode() {
        _ensureNotInRecoveryMode();
        _;
    }

    /**
     * @notice Enable recovery mode, which enables a special safe exit path for LPs.
     * @dev Does not otherwise affect pool operations (beyond deferring payment of protocol fees), though some pools may
     * perform certain operations in a "safer" manner that is less likely to fail, in an attempt to keep the pool
     * running, even in a pathological state. Unlike the Pause operation, which is only available during a short window
     * after factory deployment, Recovery Mode can always be enabled.
     */
    function enableRecoveryMode() external override authenticate {
        // Unlike when recovery mode is disabled, derived contracts should *not* do anything when it is enabled.
        // We do not want to make any calls that could fail and prevent the pool from entering recovery mode.
        // Accordingly, this should have no effect, but for consistency with `disableRecoveryMode`, revert if
        // recovery mode was already enabled.
        _ensureNotInRecoveryMode();

        _setRecoveryMode(true);

        emit RecoveryModeStateChanged(true);
    }

    /**
     * @notice Disable recovery mode, which disables the special safe exit path for LPs.
     * @dev Protocol fees are not paid while in Recovery Mode, so it should only remain active for as long as strictly
     * necessary.
     */
    function disableRecoveryMode() external override authenticate {
        // Some derived contracts respond to disabling recovery mode with state changes (e.g., related to protocol fees,
        // or otherwise ensuring that enabling and disabling recovery mode has no ill effects on LPs). When called
        // outside of recovery mode, these state changes might lead to unexpected behavior.
        _ensureInRecoveryMode();

        _setRecoveryMode(false);

        emit RecoveryModeStateChanged(false);
    }

    // Defer implementation for functions that require storage

    /**
     * @notice Override to check storage and return whether the pool is in Recovery Mode
     */
    function inRecoveryMode() public view virtual override returns (bool);

    /**
     * @dev Override to update storage and emit the event
     *
     * No complex code or external calls that could fail should be placed in the implementations,
     * which could jeopardize the ability to enable and disable Recovery Mode.
     */
    function _setRecoveryMode(bool enabled) internal virtual;

    /**
     * @dev Reverts if the contract is not in Recovery Mode.
     */
    function _ensureInRecoveryMode() internal view {
        _require(inRecoveryMode(), Errors.NOT_IN_RECOVERY_MODE);
    }

    /**
     * @dev Reverts if the contract is in Recovery Mode.
     */
    function _ensureNotInRecoveryMode() internal view {
        _require(!inRecoveryMode(), Errors.IN_RECOVERY_MODE);
    }

    /**
     * @dev A minimal proportional exit, suitable as is for most pools: though not for pools with preminted BPT
     * or other special considerations. Designed to be overridden if a pool needs to do extra processing,
     * such as scaling a stored invariant, or caching the new total supply.
     *
     * No complex code or external calls should be made in derived contracts that override this!
     */
    // function _doRecoveryModeExit(
    //     uint256[] memory balances,
    //     uint256 totalSupply,
    //     bytes memory userData
    // ) internal virtual returns (uint256, uint256[] memory);
}

/**
 * @dev The Vault does not provide the protocol swap fee percentage in swap hooks (as swaps don't typically need this
 * value), so for swaps that need this value, we would have to to fetch it ourselves from the
 * ProtocolFeePercentagesProvider. Additionally, other protocol fee types (such as Yield or AUM) can only be obtained
 * by making said call.
 *
 * However, these values change so rarely that it doesn't make sense to perform the required calls to get the current
 * values in every single user interaction. Instead, we keep a local copy that can be permissionlessly updated by anyone
 * with the real value. We also pack these values together, performing a single storage read to get them all.
 */
abstract contract ProtocolFeeCache is RecoveryMode {
    using SafeCast for uint256;
    using WordCodec for bytes32;

    // Protocol Fee IDs represent fee types; we are supporting 3 types (join, yield and aum), so 8 bits is enough to
    // store each of them.
    // [ 232 bits |   8 bits   |    8 bits    |    8 bits   ]
    // [  unused  | AUM fee ID | Yield fee ID | Swap fee ID ]
    // [MSB                                              LSB]
    uint256 private constant _FEE_TYPE_ID_WIDTH = 8;
    uint256 private constant _SWAP_FEE_ID_OFFSET = 0;
    uint256 private constant _YIELD_FEE_ID_OFFSET = _SWAP_FEE_ID_OFFSET + _FEE_TYPE_ID_WIDTH;
    uint256 private constant _AUM_FEE_ID_OFFSET = _YIELD_FEE_ID_OFFSET + _FEE_TYPE_ID_WIDTH;

    // Protocol Fee Percentages can never be larger than 100% (1e18), which fits in ~59 bits, so using 64 for each type
    // is sufficient.
    // [  64 bits |    64 bits    |     64 bits     |     64 bits    ]
    // [  unused  | AUM fee cache | Yield fee cache | Swap fee cache ]
    // [MSB                                                       LSB]
    uint256 private constant _FEE_TYPE_CACHE_WIDTH = 64;
    uint256 private constant _SWAP_FEE_OFFSET = 0;
    uint256 private constant _YIELD_FEE_OFFSET = _SWAP_FEE_OFFSET + _FEE_TYPE_CACHE_WIDTH;
    uint256 private constant _AUM_FEE_OFFSET = _YIELD_FEE_OFFSET + _FEE_TYPE_CACHE_WIDTH;

    event ProtocolFeePercentageCacheUpdated(bytes32 feeCache);

    /**
     * @dev Protocol fee types can be set at contract creation. Fee IDs store which of the IDs in the protocol fee
     * provider shall be applied to its respective fee type (swap, yield, aum).
     * This is because some Pools may have different protocol fee values for the same type of underlying operation:
     * for example, Stable Pools might have a different swap protocol fee than Weighted Pools.
     * This module does not check at all that the chosen fee types have any sort of relation with the operation they're
     * assigned to: it is possible to e.g. set a Pool's swap protocol fee to equal the flash loan protocol fee.
     */
    struct ProviderFeeIDs {
        uint256 swap;
        uint256 yield;
        uint256 aum;
    }

    IProtocolFeePercentagesProvider private immutable _protocolFeeProvider;
    bytes32 private immutable _feeIds;

    bytes32 private _feeCache;

    constructor(IProtocolFeePercentagesProvider protocolFeeProvider, ProviderFeeIDs memory providerFeeIDs) {
        _protocolFeeProvider = protocolFeeProvider;

        bytes32 feeIds = WordCodec.encodeUint(providerFeeIDs.swap, _SWAP_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH) |
            WordCodec.encodeUint(providerFeeIDs.yield, _YIELD_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH) |
            WordCodec.encodeUint(providerFeeIDs.aum, _AUM_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH);

        _feeIds = feeIds;

        _updateProtocolFeeCache(protocolFeeProvider, feeIds);
    }

    /**
     * @notice Returns the cached protocol fee percentage.
     */
    function getProtocolFeePercentageCache(uint256 feeType) public view returns (uint256) {
        if (inRecoveryMode()) {
            return 0;
        }

        uint256 offset;
        if (feeType == ProtocolFeeType.SWAP) {
            offset = _SWAP_FEE_OFFSET;
        } else if (feeType == ProtocolFeeType.YIELD) {
            offset = _YIELD_FEE_OFFSET;
        } else if (feeType == ProtocolFeeType.AUM) {
            offset = _AUM_FEE_OFFSET;
        } else {
            _revert(Errors.UNHANDLED_FEE_TYPE);
        }

        return _feeCache.decodeUint(offset, _FEE_TYPE_CACHE_WIDTH);
    }

    /**
     * @notice Returns the provider fee ID for the given fee type.
     */
    function getProviderFeeId(uint256 feeType) public view returns (uint256) {
        uint256 offset;

        if (feeType == ProtocolFeeType.SWAP) {
            offset = _SWAP_FEE_ID_OFFSET;
        } else if (feeType == ProtocolFeeType.YIELD) {
            offset = _YIELD_FEE_ID_OFFSET;
        } else if (feeType == ProtocolFeeType.AUM) {
            offset = _AUM_FEE_ID_OFFSET;
        } else {
            _revert(Errors.UNHANDLED_FEE_TYPE);
        }

        return _feeIds.decodeUint(offset, _FEE_TYPE_ID_WIDTH);
    }

    /**
     * @notice Updates the cache to the latest value set by governance.
     * @dev Can be called by anyone to update the cached fee percentages.
     */
    function updateProtocolFeePercentageCache() external {
        _beforeProtocolFeeCacheUpdate();

        _updateProtocolFeeCache(_protocolFeeProvider, _feeIds);
    }

    /**
     * @dev Override in derived contracts to perform some action before the cache is updated. This is typically relevant
     * to Pools that incur protocol debt between operations. To avoid altering the amount due retroactively, this debt
     * needs to be paid before the fee percentages change.
     */
    function _beforeProtocolFeeCacheUpdate() internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _updateProtocolFeeCache(IProtocolFeePercentagesProvider protocolFeeProvider, bytes32 feeIds) private {
        uint256 swapFee = protocolFeeProvider.getFeeTypePercentage(
            feeIds.decodeUint(_SWAP_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH)
        );
        uint256 yieldFee = protocolFeeProvider.getFeeTypePercentage(
            feeIds.decodeUint(_YIELD_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH)
        );
        uint256 aumFee = protocolFeeProvider.getFeeTypePercentage(
            feeIds.decodeUint(_AUM_FEE_ID_OFFSET, _FEE_TYPE_ID_WIDTH)
        );

        bytes32 feeCache = WordCodec.encodeUint(swapFee, _SWAP_FEE_OFFSET, _FEE_TYPE_CACHE_WIDTH) |
            WordCodec.encodeUint(yieldFee, _YIELD_FEE_OFFSET, _FEE_TYPE_CACHE_WIDTH) |
            WordCodec.encodeUint(aumFee, _AUM_FEE_OFFSET, _FEE_TYPE_CACHE_WIDTH);

        _feeCache = feeCache;

        emit ProtocolFeePercentageCacheUpdated(feeCache);
    }
}



library ExternalAUMFees {
    /**
     * @notice Calculates the amount of BPT to mint to pay AUM fees accrued since the last collection.
     * @dev This calculation assumes that the Pool's total supply is constant over the fee period.
     *
     * When paying AUM fees over short durations, significant rounding errors can be introduced when converting from a
     * percentage of the pool to a BPT amount. To combat this, we convert the yearly percentage to BPT and then scale
     * appropriately.
     */
    function getAumFeesBptAmount(
        uint256 totalSupply,
        uint256 currentTime,
        uint256 lastCollection,
        uint256 annualAumFeePercentage
    ) internal pure returns (uint256) {
        // If no time has passed since the last collection then clearly no fees are accrued so we can return early.
        // We also perform an early return if the AUM fee is zero.
        if (currentTime <= lastCollection || annualAumFeePercentage == 0) return 0;

        uint256 annualBptAmount = ExternalFees.bptForPoolOwnershipPercentage(totalSupply, annualAumFeePercentage);

        // We want to collect fees so that after a year the Pool will have paid `annualAumFeePercentage` of its AUM as
        // fees. In normal operation however, we will collect fees regularly over the course of the year so we
        // multiply `annualBptAmount` by the fraction of the year which has elapsed since we last collected fees.
        uint256 elapsedTime = currentTime - lastCollection;

        // As an example for this calculate, consider a pool with a total supply of 1000e18 BPT, AUM fees are charged
        // at 5% yearly and it's been 7 days since the last collection of AUM fees. The expected fees are then:
        //
        // expected_yearly_fees = totalSupply * annualAumFeePercentage / (1 - annualAumFeePercentage)
        //                      = 1000e18 * 0.05 / 0.95
        //                      ~= 52.63e18 BPT
        //
        // fees_to_collect = expected_yearly_fees * time_since_last_collection / 1 year
        //                 = 52.63e18 * 7 / 365
        //                 ~= 1.009 BPT
        //
        // Note that if we were to mint expected_yearly_fees BPT then the recipient would own 52.63e18 out of
        // 1052.63e18 BPT. This agrees with the recipient being expected to own 5% of the Pool *after* fees are paid.

        // Like with all other fees, we round down, favoring LPs.
        return Math.divDown(Math.mul(annualBptAmount, elapsedTime), 365 days);
    }
}




/**
 * @dev IPools with the General specialization setting should implement this interface.
 *
 * This is called by the Vault when a user calls `IVault.swap` or `IVault.batchSwap` to swap with this Pool.
 * Returns the number of tokens the Pool will grant to the user in a 'given in' swap, or that the user will
 * grant to the pool in a 'given out' swap.
 *
 * This can often be implemented by a `view` function, since many pricing algorithms don't need to track state
 * changes in swaps. However, contracts implementing this in non-view functions should check that the caller is
 * indeed the Vault.
 */
interface IGeneralPool is IBasePool {
    function onSwap(
        SwapRequest memory swapRequest,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) external returns (uint256 amount);
}



/**
 * @dev Pool contracts with the MinimalSwapInfo or TwoToken specialization settings should implement this interface.
 *
 * This is called by the Vault when a user calls `IVault.swap` or `IVault.batchSwap` to swap with this Pool.
 * Returns the number of tokens the Pool will grant to the user in a 'given in' swap, or that the user will grant
 * to the pool in a 'given out' swap.
 *
 * This can often be implemented by a `view` function, since many pricing algorithms don't need to track state
 * changes in swaps. However, contracts implementing this in non-view functions should check that the caller is
 * indeed the Vault.
 */
interface IMinimalSwapInfoPool is IBasePool {
    function onSwap(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external returns (uint256 amount);
}


/**
 * @dev Allows for a contract to be paused during an initial period after deployment, disabling functionality. Can be
 * used as an emergency switch in case a security vulnerability or threat is identified.
 *
 * The contract can only be paused during the Pause Window, a period that starts at deployment. It can also be
 * unpaused and repaused any number of times during this period. This is intended to serve as a safety measure: it lets
 * system managers react quickly to potentially dangerous situations, knowing that this action is reversible if careful
 * analysis later determines there was a false alarm.
 *
 * If the contract is paused when the Pause Window finishes, it will remain in the paused state through an additional
 * Buffer Period, after which it will be automatically unpaused forever. This is to ensure there is always enough time
 * to react to an emergency, even if the threat is discovered shortly before the Pause Window expires.
 *
 * Note that since the contract can only be paused within the Pause Window, unpausing during the Buffer Period is
 * irreversible.
 */
abstract contract TemporarilyPausable is ITemporarilyPausable {
    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 private immutable _pauseWindowEndTime;
    uint256 private immutable _bufferPeriodEndTime;

    bool private _paused;

    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration) {
        _require(pauseWindowDuration <= PausableConstants.MAX_PAUSE_WINDOW_DURATION, Errors.MAX_PAUSE_WINDOW_DURATION);
        _require(
            bufferPeriodDuration <= PausableConstants.MAX_BUFFER_PERIOD_DURATION,
            Errors.MAX_BUFFER_PERIOD_DURATION
        );

        uint256 pauseWindowEndTime = block.timestamp + pauseWindowDuration;

        _pauseWindowEndTime = pauseWindowEndTime;
        _bufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;
    }

    /**
     * @dev Reverts if the contract is paused.
     */
    modifier whenNotPaused() {
        _ensureNotPaused();
        _;
    }

    /**
     * @dev Returns the current contract pause status, as well as the end times of the Pause Window and Buffer
     * Period.
     */
    function getPausedState()
        external
        view
        override
        returns (
            bool paused,
            uint256 pauseWindowEndTime,
            uint256 bufferPeriodEndTime
        )
    {
        paused = !_isNotPaused();
        pauseWindowEndTime = _getPauseWindowEndTime();
        bufferPeriodEndTime = _getBufferPeriodEndTime();
    }

    /**
     * @dev Sets the pause state to `paused`. The contract can only be paused until the end of the Pause Window, and
     * unpaused until the end of the Buffer Period.
     *
     * Once the Buffer Period expires, this function reverts unconditionally.
     */
    function _setPaused(bool paused) internal {
        if (paused) {
            _require(block.timestamp < _getPauseWindowEndTime(), Errors.PAUSE_WINDOW_EXPIRED);
        } else {
            _require(block.timestamp < _getBufferPeriodEndTime(), Errors.BUFFER_PERIOD_EXPIRED);
        }

        _paused = paused;
        emit PausedStateChanged(paused);
    }

    /**
     * @dev Reverts if the contract is paused.
     */
    function _ensureNotPaused() internal view {
        _require(_isNotPaused(), Errors.PAUSED);
    }

    /**
     * @dev Reverts if the contract is not paused.
     */
    function _ensurePaused() internal view {
        _require(!_isNotPaused(), Errors.NOT_PAUSED);
    }

    /**
     * @dev Returns true if the contract is unpaused.
     *
     * Once the Buffer Period expires, the gas cost of calling this function is reduced dramatically, as storage is no
     * longer accessed.
     */
    function _isNotPaused() internal view returns (bool) {
        // After the Buffer Period, the (inexpensive) timestamp check short-circuits the storage access.
        return block.timestamp > _getBufferPeriodEndTime() || !_paused;
    }

    // These getters lead to reduced bytecode size by inlining the immutable variables in a single place.

    function _getPauseWindowEndTime() private view returns (uint256) {
        return _pauseWindowEndTime;
    }

    function _getBufferPeriodEndTime() private view returns (uint256) {
        return _bufferPeriodEndTime;
    }
}

/**
 * @dev Keep the maximum durations in a single place.
 */
library PausableConstants {
    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 270 days;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;
}



/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on `{IERC20-approve}`, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over `owner`'s tokens,
     * given `owner`'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for `permit`, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}


/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP 712] is a standard for hashing and signing of typed structured data.
 *
 * The encoding specified in the EIP is very generic, and such a generic implementation in Solidity is not feasible,
 * thus this contract does not implement the encoding itself. Protocols need to implement the type-specific encoding
 * they need in their contracts using a combination of `abi.encode` and `keccak256`.
 *
 * This contract implements the EIP 712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest that is then signed via ECDSA
 * ({_hashTypedDataV4}).
 *
 * The implementation of the domain separator was designed to be as efficient as possible while still properly updating
 * the chain id to protect against replay attacks on an eventual fork of the chain.
 *
 * NOTE: This contract implements the version of the encoding known as "v4", as implemented by the JSON RPC method
 * https://docs.metamask.io/guide/signing-data.html[`eth_signTypedDataV4` in MetaMask].
 *
 * _Available since v3.4._
 */
abstract contract EIP712 {
    /* solhint-disable var-name-mixedcase */
    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    /* solhint-enable var-name-mixedcase */

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP 712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        _HASHED_NAME = keccak256(bytes(name));
        _HASHED_VERSION = keccak256(bytes(version));
        _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view virtual returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, _getChainId(), address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    // solc-ignore-next-line func-mutability
    function _getChainId() private view returns (uint256 chainId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }
}

/**
 * @dev Utility for signing Solidity function calls.
 */
abstract contract EOASignaturesValidator is ISignaturesValidator, EIP712 {
    // Replay attack prevention for each account.
    mapping(address => uint256) internal _nextNonce;

    function getDomainSeparator() public view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function getNextNonce(address account) public view override returns (uint256) {
        return _nextNonce[account];
    }

    function _ensureValidSignature(
        address account,
        bytes32 structHash,
        bytes memory signature,
        uint256 errorCode
    ) internal {
        return _ensureValidSignature(account, structHash, signature, type(uint256).max, errorCode);
    }

    function _ensureValidSignature(
        address account,
        bytes32 structHash,
        bytes memory signature,
        uint256 deadline,
        uint256 errorCode
    ) internal {
        bytes32 digest = _hashTypedDataV4(structHash);
        _require(_isValidSignature(account, digest, signature), errorCode);

        // We could check for the deadline before validating the signature, but this leads to saner error processing (as
        // we only care about expired deadlines if the signature is correct) and only affects the gas cost of the revert
        // scenario, which will only occur infrequently, if ever.
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        _require(deadline >= block.timestamp, Errors.EXPIRED_SIGNATURE);

        // We only advance the nonce after validating the signature. This is irrelevant for this module, but it can be
        // important in derived contracts that override _isValidSignature (e.g. SignaturesValidator), as we want for
        // the observable state to still have the current nonce as the next valid one.
        _nextNonce[account] += 1;
    }

    function _isValidSignature(
        address account,
        bytes32 digest,
        bytes memory signature
    ) internal view virtual returns (bool) {
        _require(signature.length == 65, Errors.MALFORMED_SIGNATURE);

        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the r, s and v signature parameters, and the only way to get them is to use assembly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        address recoveredAddress = ecrecover(digest, v, r, s);

        // ecrecover returns the zero address on recover failure, so we need to handle that explicitly.
        return (recoveredAddress != address(0) && recoveredAddress == account);
    }

    function _toArraySignature(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(signature, 32), r)
            mstore(add(signature, 64), s)
            mstore8(add(signature, 96), v)
        }

        return signature;
    }
}

/**
 * @dev Implementation of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on `{IERC20-approve}`, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * _Available since v3.4._
 */
abstract contract ERC20Permit is ERC20, IERC20Permit, EOASignaturesValidator {
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 token name.
     */
    constructor(string memory name) EIP712(name, "1") {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev See {IERC20Permit-permit}.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        bytes32 structHash = keccak256(
            abi.encode(_PERMIT_TYPEHASH, owner, spender, value, getNextNonce(owner), deadline)
        );

        _ensureValidSignature(owner, structHash, _toArraySignature(v, r, s), deadline, Errors.INVALID_SIGNATURE);

        _approve(owner, spender, value);
    }

    /**
     * @dev See {IERC20Permit-nonces}.
     */
    function nonces(address owner) public view override returns (uint256) {
        return getNextNonce(owner);
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return getDomainSeparator();
    }
}

/**
 * @title Highly opinionated token implementation
 * @author Balancer Labs
 * @dev
 * - Includes functions to increase and decrease allowance as a workaround
 *   for the well-known issue with `approve`:
 *   https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
 * - Allows for 'infinite allowance', where an allowance of 0xff..ff is not
 *   decreased by calls to transferFrom
 * - Lets a token holder use `transferFrom` to send their own tokens,
 *   without first setting allowance
 * - Emits 'Approval' events whenever allowance is changed by `transferFrom`
 * - Assigns infinite allowance for all token holders to the Vault
 */
contract BalancerPoolToken is ERC20Permit {
    IVault private immutable _vault;

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        IVault vault
    ) ERC20(tokenName, tokenSymbol) ERC20Permit(tokenName) {
        _vault = vault;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    // Overrides

    /**
     * @dev Override to grant the Vault infinite allowance, causing for Pool Tokens to not require approval.
     *
     * This is sound as the Vault already provides authorization mechanisms when initiation token transfers, which this
     * contract inherits.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == address(getVault())) {
            return uint256(-1);
        } else {
            return super.allowance(owner, spender);
        }
    }

    /**
     * @dev Override to allow for 'infinite allowance' and let the token owner use `transferFrom` with no self-allowance
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentAllowance = allowance(sender, msg.sender);
        _require(msg.sender == sender || currentAllowance >= amount, Errors.ERC20_TRANSFER_EXCEEDS_ALLOWANCE);

        _transfer(sender, recipient, amount);

        if (msg.sender != sender && currentAllowance != uint256(-1)) {
            // Because of the previous require, we know that if msg.sender != sender then currentAllowance >= amount
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Override to allow decreasing allowance by more than the current amount (setting it to zero)
     */
    function decreaseAllowance(address spender, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);

        if (amount >= currentAllowance) {
            _approve(msg.sender, spender, 0);
        } else {
            // No risk of underflow due to if condition
            _approve(msg.sender, spender, currentAllowance - amount);
        }

        return true;
    }

    // Internal functions

    function _mintPoolTokens(address recipient, uint256 amount) internal {
        _mint(recipient, amount);
    }

    function _burnPoolTokens(address sender, uint256 amount) internal {
        _burn(sender, amount);
    }
}

// solhint-disable max-states-count

/**
 * @notice Reference implementation for the base layer of a Pool contract.
 * @dev Reference implementation for the base layer of a Pool contract that manages a single Pool with optional
 * Asset Managers, an admin-controlled swap fee percentage, and an emergency pause mechanism.
 *
 * This Pool pays protocol fees by minting BPT directly to the ProtocolFeeCollector instead of using the
 * `dueProtocolFees` return value. This results in the underlying tokens continuing to provide liquidity
 * for traders, while still keeping gas usage to a minimum since only a single token (the BPT) is transferred.
 *
 * Note that neither swap fees nor the pause mechanism are used by this contract. They are passed through so that
 * derived contracts can use them via the `_addSwapFeeAmount` and `_subtractSwapFeeAmount` functions, and the
 * `whenNotPaused` modifier.
 *
 * No admin permissions are checked here: instead, this contract delegates that to the Vault's own Authorizer.
 *
 * Because this contract doesn't implement the swap hooks, derived contracts should generally inherit from
 * BaseGeneralPool or BaseMinimalSwapInfoPool. Otherwise, subclasses must inherit from the corresponding interfaces
 * and implement the swap callbacks themselves.
 */
abstract contract NewBasePool is
    IBasePool,
    IGeneralPool,
    IMinimalSwapInfoPool,
    BasePoolAuthorization,
    BalancerPoolToken,
    TemporarilyPausable,
    RecoveryMode
{
    using BasePoolUserData for bytes;

    uint256 private constant _DEFAULT_MINIMUM_BPT = 1e6;

    bytes32 private immutable _poolId;

    // Note that this value is immutable in the Vault, so we can make it immutable here and save gas
    IProtocolFeesCollector private immutable _protocolFeesCollector;

    constructor(
        IVault vault,
        bytes32 poolId,
        string memory name,
        string memory symbol,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    )
        // Base Pools are expected to be deployed using factories. By using the factory address as the action
        // disambiguator, we make all Pools deployed by the same factory share action identifiers. This allows for
        // simpler management of permissions (such as being able to manage granting the 'set fee percentage' action in
        // any Pool created by the same factory), while still making action identifiers unique among different factories
        // if the selectors match, preventing accidental errors.
        Authentication(bytes32(uint256(msg.sender)))
        BalancerPoolToken(name, symbol, vault)
        BasePoolAuthorization(owner)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {
        // Set immutable state variables - these cannot be read from during construction
        _poolId = poolId;
        _protocolFeesCollector = vault.getProtocolFeesCollector();
    }

    // Getters

    /**
     * @notice Return the pool id.
     */
    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function _getAuthorizer() internal view override returns (IAuthorizer) {
        // Access control management is delegated to the Vault's Authorizer. This lets Balancer Governance manage which
        // accounts can call permissioned functions: for example, to perform emergency pauses.
        // If the owner is delegated, then *all* permissioned functions, including `updateSwapFeeGradually`, will be
        // under Governance control.
        return getVault().getAuthorizer();
    }

    /**
     * @dev Returns the minimum BPT supply. This amount is minted to the zero address during initialization, effectively
     * locking it.
     *
     * This is useful to make sure Pool initialization happens only once, but derived Pools can change this value (even
     * to zero) by overriding this function.
     */
    function _getMinimumBpt() internal pure virtual returns (uint256) {
        return _DEFAULT_MINIMUM_BPT;
    }

    // Protocol Fees

    /**
     * @notice Return the ProtocolFeesCollector contract.
     * @dev This is immutable, and retrieved from the Vault on construction. (It is also immutable in the Vault.)
     */
    function getProtocolFeesCollector() public view returns (IProtocolFeesCollector) {
        return _protocolFeesCollector;
    }

    /**
     * @dev Pays protocol fees by minting `bptAmount` to the Protocol Fee Collector.
     */
    function _payProtocolFees(uint256 bptAmount) internal {
        if (bptAmount > 0) {
            _mintPoolTokens(address(getProtocolFeesCollector()), bptAmount);
        }
    }

    /**
     * @notice Pause the pool: an emergency action which disables all pool functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during pool factory
     * deployment (see `TemporarilyPausable`).
     */
    function pause() external authenticate {
        _setPaused(true);
    }

    /**
     * @notice Reverse a `pause` operation, and restore a pool to normal functionality.
     * @dev This is a permissioned function that will only work on a paused pool within the Buffer Period set during
     * pool factory deployment (see `TemporarilyPausable`). Note that any paused pools will automatically unpause
     * after the Buffer Period expires.
     */
    function unpause() external authenticate {
        _setPaused(false);
    }

    modifier onlyVault(bytes32 poolId) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }

    // Swap / Join / Exit Hooks

    function onSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    ) external override onlyVault(request.poolId) returns (uint256) {
        _ensureNotPaused();

        return _onSwapMinimal(request, balanceTokenIn, balanceTokenOut);
    }

    function _onSwapMinimal(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    ) internal virtual returns (uint256);

    function onSwap(
        SwapRequest memory request,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) external override onlyVault(request.poolId) returns (uint256) {
        _ensureNotPaused();

        return _onSwapGeneral(request, balances, indexIn, indexOut);
    }

    function _onSwapGeneral(
        SwapRequest memory request,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) internal virtual returns (uint256);

    /**
     * @notice Vault hook for adding liquidity to a pool (including the first time, "initializing" the pool).
     * @dev This function can only be called from the Vault, from `joinPool`.
     */
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256,
        uint256,
        bytes memory userData
    ) external override onlyVault(poolId) returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFees) {
        uint256 bptAmountOut;

        _ensureNotPaused();
        if (totalSupply() == 0) {
            (bptAmountOut, amountsIn) = _onInitializePool(sender, recipient, userData);

            // On initialization, we lock _getMinimumBpt() by minting it for the zero address. This BPT acts as a
            // minimum as it will never be burned, which reduces potential issues with rounding, and also prevents the
            // Pool from ever being fully drained.
            // Some pool types do not require this mechanism, and the minimum BPT might be zero.
            _require(bptAmountOut >= _getMinimumBpt(), Errors.MINIMUM_BPT);
            _mintPoolTokens(address(0), _getMinimumBpt());

            _mintPoolTokens(recipient, bptAmountOut - _getMinimumBpt());
        } else {
            (bptAmountOut, amountsIn) = _onJoinPool(sender, balances, userData);

            // Note we no longer use `balances` after calling `_onJoinPool`, which may mutate it.

            _mintPoolTokens(recipient, bptAmountOut);
        }

        // This Pool ignores the `dueProtocolFees` return value, so we simply return a zeroed-out array.
        dueProtocolFees = new uint256[](amountsIn.length);
    }

    /**
     * @notice Vault hook for removing liquidity from a pool.
     * @dev This function can only be called from the Vault, from `exitPool`.
     */
    function onExitPool(
        bytes32 poolId,
        address sender,
        address,
        uint256[] memory balances,
        uint256,
        uint256,
        bytes memory userData
    ) external override onlyVault(poolId) returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFees) {
        uint256 bptAmountIn;

        // When a user calls `exitPool`, this is the first point of entry from the Vault.
        // We first check whether this is a Recovery Mode exit - if so, we proceed using this special lightweight exit
        // mechanism which avoids computing any complex values, interacting with external contracts, etc., and generally
        // should always work, even if the Pool's mathematics or a dependency break down.
        if (userData.isRecoveryModeExitKind()) {
            // This exit kind is only available in Recovery Mode.
            _ensureInRecoveryMode();

            // Note that we don't upscale balances nor downscale amountsOut - we don't care about scaling factors during
            // a recovery mode exit.
            // (bptAmountIn, amountsOut) = _doRecoveryModeExit(balances, totalSupply(), userData);
        } else {
            // Note that we only call this if we're not in a recovery mode exit.
            _ensureNotPaused();

            (bptAmountIn, amountsOut) = _onExitPool(sender, balances, userData);
        }

        // Note we no longer use `balances` after calling `_onExitPool`, which may mutate it.

        _burnPoolTokens(sender, bptAmountIn);

        // This Pool ignores the `dueProtocolFees` return value, so we simply return a zeroed-out array.
        dueProtocolFees = new uint256[](amountsOut.length);
    }

    // Query functions

    /**
     * @notice "Dry run" `onJoinPool`.
     * @dev Returns the amount of BPT that would be granted to `recipient` if the `onJoinPool` hook were called by the
     * Vault with the same arguments, along with the number of tokens `sender` would have to supply.
     *
     * This function is not meant to be called directly, but rather from a helper contract that fetches current Vault
     * data, such as the protocol swap fee percentage and Pool balances.
     *
     * Like `IVault.queryBatchSwap`, this function is not view due to internal implementation details: the caller must
     * explicitly use eth_call instead of eth_sendTransaction.
     */
    function queryJoin(
        bytes32,
        address sender,
        address,
        uint256[] memory balances,
        uint256,
        uint256,
        bytes memory userData
    ) external override returns (uint256 bptOut, uint256[] memory amountsIn) {
        _queryAction(sender, balances, userData, _onJoinPool);

        // The `return` opcode is executed directly inside `_queryAction`, so execution never reaches this statement,
        // and we don't need to return anything here - it just silences compiler warnings.
        return (bptOut, amountsIn);
    }

    /**
     * @notice "Dry run" `onExitPool`.
     * @dev Returns the amount of BPT that would be burned from `sender` if the `onExitPool` hook were called by the
     * Vault with the same arguments, along with the number of tokens `recipient` would receive.
     *
     * This function is not meant to be called directly, but rather from a helper contract that fetches current Vault
     * data, such as the protocol swap fee percentage and Pool balances.
     *
     * Like `IVault.queryBatchSwap`, this function is not view due to internal implementation details: the caller must
     * explicitly use eth_call instead of eth_sendTransaction.
     */
    function queryExit(
        bytes32,
        address sender,
        address,
        uint256[] memory balances,
        uint256,
        uint256,
        bytes memory userData
    ) external override returns (uint256 bptIn, uint256[] memory amountsOut) {
        _queryAction(sender, balances, userData, _onExitPool);

        // The `return` opcode is executed directly inside `_queryAction`, so execution never reaches this statement,
        // and we don't need to return anything here - it just silences compiler warnings.
        return (bptIn, amountsOut);
    }

    // Internal hooks to be overridden by derived contracts - all token amounts (except BPT) in these interfaces are
    // upscaled.

    /**
     * @dev Called when the Pool is joined for the first time; that is, when the BPT total supply is zero.
     *
     * Returns the amount of BPT to mint, and the token amounts the Pool will receive in return.
     *
     * Minted BPT will be sent to `recipient`, except for _getMinimumBpt(), which will be deducted from this amount and
     * sent to the zero address instead. This will cause that BPT to remain forever locked there, preventing total BTP
     * from ever dropping below that value, and ensuring `_onInitializePool` can only be called once in the entire
     * Pool's lifetime.
     *
     * The tokens granted to the Pool will be transferred from `sender`. These amounts are considered upscaled and will
     * be downscaled (rounding up) before being returned to the Vault.
     */
    function _onInitializePool(
        address sender,
        address recipient,
        bytes memory userData
    ) internal virtual returns (uint256 bptAmountOut, uint256[] memory amountsIn);

    /**
     * @dev Called whenever the Pool is joined after the first initialization join (see `_onInitializePool`).
     *
     * Returns the amount of BPT to mint, the token amounts that the Pool will receive in return, and the number of
     * tokens to pay in protocol swap fees.
     *
     * Implementations of this function might choose to mutate the `balances` array to save gas (e.g. when
     * performing intermediate calculations, such as subtraction of due protocol fees). This can be done safely.
     *
     * Minted BPT will be sent to `recipient`.
     *
     * The tokens granted to the Pool will be transferred from `sender`. These amounts are considered upscaled and will
     * be downscaled (rounding up) before being returned to the Vault.
     *
     * Due protocol swap fees will be taken from the Pool's balance in the Vault (see `IBasePool.onJoinPool`). These
     * amounts are considered upscaled and will be downscaled (rounding down) before being returned to the Vault.
     */
    function _onJoinPool(
        address sender,
        uint256[] memory balances,
        bytes memory userData
    ) internal virtual returns (uint256 bptAmountOut, uint256[] memory amountsIn);

    /**
     * @dev Called whenever the Pool is exited.
     *
     * Returns the amount of BPT to burn, the token amounts for each Pool token that the Pool will grant in return, and
     * the number of tokens to pay in protocol swap fees.
     *
     * Implementations of this function might choose to mutate the `balances` array to save gas (e.g. when
     * performing intermediate calculations, such as subtraction of due protocol fees). This can be done safely.
     *
     * BPT will be burnt from `sender`.
     *
     * The Pool will grant tokens to `recipient`. These amounts are considered upscaled and will be downscaled
     * (rounding down) before being returned to the Vault.
     *
     * Due protocol swap fees will be taken from the Pool's balance in the Vault (see `IBasePool.onExitPool`). These
     * amounts are considered upscaled and will be downscaled (rounding down) before being returned to the Vault.
     */
    function _onExitPool(
        address sender,
        uint256[] memory balances,
        bytes memory userData
    ) internal virtual returns (uint256 bptAmountIn, uint256[] memory amountsOut);

    function _queryAction(
        address sender,
        uint256[] memory balances,
        bytes memory userData,
        function(address, uint256[] memory, bytes memory) internal returns (uint256, uint256[] memory) _action
    ) private {
        // This uses the same technique used by the Vault in queryBatchSwap. Refer to that function for a detailed
        // explanation.

        if (msg.sender != address(this)) {
            // We perform an external call to ourselves, forwarding the same calldata. In this call, the else clause of
            // the preceding if statement will be executed instead.

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(this).call(msg.data);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // This call should always revert to decode the bpt and token amounts from the revert reason
                switch success
                    case 0 {
                        // Note we are manually writing the memory slot 0. We can safely overwrite whatever is
                        // stored there as we take full control of the execution and then immediately return.

                        // We copy the first 4 bytes to check if it matches with the expected signature, otherwise
                        // there was another revert reason and we should forward it.
                        returndatacopy(0, 0, 0x04)
                        let error := and(mload(0), 0xffffffff00000000000000000000000000000000000000000000000000000000)

                        // If the first 4 bytes don't match with the expected signature, we forward the revert reason.
                        if eq(eq(error, 0x43adbafb00000000000000000000000000000000000000000000000000000000), 0) {
                            returndatacopy(0, 0, returndatasize())
                            revert(0, returndatasize())
                        }

                        // The returndata contains the signature, followed by the raw memory representation of the
                        // `bptAmount` and `tokenAmounts` (array: length + data). We need to return an ABI-encoded
                        // representation of these.
                        // An ABI-encoded response will include one additional field to indicate the starting offset of
                        // the `tokenAmounts` array. The `bptAmount` will be laid out in the first word of the
                        // returndata.
                        //
                        // In returndata:
                        // [ signature ][ bptAmount ][ tokenAmounts length ][ tokenAmounts values ]
                        // [  4 bytes  ][  32 bytes ][       32 bytes      ][ (32 * length) bytes ]
                        //
                        // We now need to return (ABI-encoded values):
                        // [ bptAmount ][ tokeAmounts offset ][ tokenAmounts length ][ tokenAmounts values ]
                        // [  32 bytes ][       32 bytes     ][       32 bytes      ][ (32 * length) bytes ]

                        // We copy 32 bytes for the `bptAmount` from returndata into memory.
                        // Note that we skip the first 4 bytes for the error signature
                        returndatacopy(0, 0x04, 32)

                        // The offsets are 32-bytes long, so the array of `tokenAmounts` will start after
                        // the initial 64 bytes.
                        mstore(0x20, 64)

                        // We now copy the raw memory array for the `tokenAmounts` from returndata into memory.
                        // Since bpt amount and offset take up 64 bytes, we start copying at address 0x40. We also
                        // skip the first 36 bytes from returndata, which correspond to the signature plus bpt amount.
                        returndatacopy(0x40, 0x24, sub(returndatasize(), 36))

                        // We finally return the ABI-encoded uint256 and the array, which has a total length equal to
                        // the size of returndata, plus the 32 bytes of the offset but without the 4 bytes of the
                        // error signature.
                        return(0, add(returndatasize(), 28))
                    }
                    default {
                        // This call should always revert, but we fail nonetheless if that didn't happen
                        invalid()
                    }
            }
        } else {
            (uint256 bptAmount, uint256[] memory tokenAmounts) = _action(sender, balances, userData);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // We will return a raw representation of `bptAmount` and `tokenAmounts` in memory, which is composed of
                // a 32-byte uint256, followed by a 32-byte for the array length, and finally the 32-byte uint256 values
                // Because revert expects a size in bytes, we multiply the array length (stored at `tokenAmounts`) by 32
                let size := mul(mload(tokenAmounts), 32)

                // We store the `bptAmount` in the previous slot to the `tokenAmounts` array. We can make sure there
                // will be at least one available slot due to how the memory scratch space works.
                // We can safely overwrite whatever is stored in this slot as we will revert immediately after that.
                let start := sub(tokenAmounts, 0x20)
                mstore(start, bptAmount)

                // We send one extra value for the error signature "QueryError(uint256,uint256[])" which is 0x43adbafb
                // We use the previous slot to `bptAmount`.
                mstore(sub(start, 0x20), 0x0000000000000000000000000000000000000000000000000000000043adbafb)
                start := sub(start, 0x04)

                // When copying from `tokenAmounts` into returndata, we copy the additional 68 bytes to also return
                // the `bptAmount`, the array 's length, and the error signature.
                revert(start, add(size, 68))
            }
        }
    }
}

import "./GradualValueChange.sol";











/**
 * @title Managed Pool AUM Storage Library
 * @notice Library for manipulating a bitmap used for Pool state used for charging AUM fees in ManagedPool.
 */
library ManagedPoolAumStorageLib {
    using WordCodec for bytes32;

    // Store AUM fee values:
    // Percentage of AUM to be paid as fees yearly.
    // Timestamp of the most recent collection of AUM fees.
    //
    // [  164 bit |        32 bits       |    60 bits   ]
    // [  unused  | last collection time | aum fee pct. ]
    // |MSB                                          LSB|
    uint256 private constant _AUM_FEE_PERCENTAGE_OFFSET = 0;
    uint256 private constant _LAST_COLLECTION_TIMESTAMP_OFFSET = _AUM_FEE_PERCENTAGE_OFFSET + _AUM_FEE_PCT_WIDTH;

    uint256 private constant _TIMESTAMP_WIDTH = 32;
    // 2**60 ~= 1.1e18 so this is sufficient to store the full range of potential AUM fees.
    uint256 private constant _AUM_FEE_PCT_WIDTH = 60;

    // Getters

    /**
     * @notice Returns the current AUM fee percentage and the timestamp of the last fee collection.
     * @param aumState - The byte32 state of the Pool's AUM fees.
     * @return aumFeePercentage - The percentage of the AUM of the Pool to be charged as fees yearly.
     * @return lastCollectionTimestamp - The timestamp of the last collection of AUM fees.
     */
    function getAumFeeFields(bytes32 aumState)
        internal
        pure
        returns (uint256 aumFeePercentage, uint256 lastCollectionTimestamp)
    {
        aumFeePercentage = aumState.decodeUint(_AUM_FEE_PERCENTAGE_OFFSET, _AUM_FEE_PCT_WIDTH);
        lastCollectionTimestamp = aumState.decodeUint(_LAST_COLLECTION_TIMESTAMP_OFFSET, _TIMESTAMP_WIDTH);
    }

    // Setters

    /**
     * @notice Sets the AUM fee percentage describing what fraction of the Pool should be charged as fees yearly.
     * @param aumState - The byte32 state of the Pool's AUM fees.
     * @param aumFeePercentage - The new percentage of the AUM of the Pool to be charged as fees yearly.
     */
    function setAumFeePercentage(bytes32 aumState, uint256 aumFeePercentage) internal pure returns (bytes32) {
        return aumState.insertUint(aumFeePercentage, _AUM_FEE_PERCENTAGE_OFFSET, _AUM_FEE_PCT_WIDTH);
    }

    /**
     * @notice Sets the timestamp of the last collection of AUM fees
     * @param aumState - The byte32 state of the Pool's AUM fees.
     * @param timestamp - The timestamp of the last collection of AUM fees. `block.timestamp` should usually be passed.
     */
    function setLastCollectionTimestamp(bytes32 aumState, uint256 timestamp) internal pure returns (bytes32) {
        return aumState.insertUint(timestamp, _LAST_COLLECTION_TIMESTAMP_OFFSET, _TIMESTAMP_WIDTH);
    }
}

import "./ManagedPoolStorageLib.sol";
import "./ManagedPoolAddRemoveTokenLib.sol";
import "./CircuitBreakerStorageLib.sol";

/**
 * @title Managed Pool Settings
 */
abstract contract ManagedPoolSettings is NewBasePool, ProtocolFeeCache, IManagedPool {
    // ManagedPool weights and swap fees can change over time: these periods are expected to be long enough (e.g. days)
    // that any timestamp manipulation would achieve very little.
    // solhint-disable not-rely-on-time

    using FixedPoint for uint256;
    using WeightedPoolUserData for bytes;

    // State variables

    uint256 private constant _MIN_TOKENS = 2;
    // The upper bound is WeightedMath.MAX_WEIGHTED_TOKENS, but this is constrained by other factors, such as Pool
    // creation gas consumption.
    uint256 private constant _MAX_TOKENS = 50;

    // The swap fee cannot be 100%: calculations that divide by (1-fee) would revert with division by zero.
    // Swap fees close to 100% can still cause reverts when performing join/exit swaps, if the calculated fee
    // amounts exceed the pool's token balances in the Vault. 95% is a very high but safe maximum value, and we want to
    // be permissive to let the owner manage the Pool as they see fit.
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 95e16; // 95%

    // The same logic applies to the AUM fee.
    uint256 private constant _MAX_MANAGEMENT_AUM_FEE_PERCENTAGE = 95e16; // 95%

    // We impose a minimum swap fee to create some buy/sell spread, and prevent the Pool from being drained through
    // repeated interactions. We should not need this since we explicity always round favoring the Pool, but a minimum
    // swap fee adds an extra safeguard.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%

    // Stores commonly used Pool state.
    // This slot is preferred for gas-sensitive operations as it is read in all joins, swaps and exits,
    // and therefore warm.
    // See `ManagedPoolStorageLib.sol` for data layout.
    bytes32 private _poolState;

    // Stores state related to charging AUM fees.
    // See `ManagedPoolAUMStorageLib.sol` for data layout.
    bytes32 private _aumState;

    // Store scaling factor and start/end normalized weights for each token.
    // See `ManagedPoolTokenStorageLib.sol` for data layout.
    mapping(IERC20 => bytes32) private _tokenState;

    // Store the circuit breaker configuration for each token.
    // See `CircuitBreakerStorageLib.sol` for data layout.
    mapping(IERC20 => bytes32) private _circuitBreakerState;

    // If mustAllowlistLPs is enabled, this is the list of addresses allowed to join the pool
    mapping(address => bool) private _allowedAddresses;


    struct ManagedPoolSettingsParams {
        IERC20[] tokens;
        uint256[] normalizedWeights;
        uint256 swapFeePercentage;
        bool swapEnabledOnStart;
        bool mustAllowlistLPs;
        uint256 managementAumFeePercentage;
        uint256 aumFeeId;
    }

    constructor(ManagedPoolSettingsParams memory params, IProtocolFeePercentagesProvider protocolFeeProvider)
        ProtocolFeeCache(
            protocolFeeProvider,
            ProviderFeeIDs({ swap: ProtocolFeeType.SWAP, yield: ProtocolFeeType.YIELD, aum: params.aumFeeId })
        )
    {
        uint256 totalTokens = params.tokens.length;
        _require(totalTokens >= _MIN_TOKENS, Errors.MIN_TOKENS);
        _require(totalTokens <= _MAX_TOKENS, Errors.MAX_TOKENS);

        InputHelpers.ensureInputLengthMatch(totalTokens, params.normalizedWeights.length);

        // Validate and set initial fees
        _setManagementAumFeePercentage(params.managementAumFeePercentage);

        // Initialize the tokens' states with their scaling factors and weights.
        for (uint256 i = 0; i < totalTokens; i++) {
            IERC20 token = params.tokens[i];
            _tokenState[token] = ManagedPoolTokenStorageLib.initializeTokenState(token, params.normalizedWeights[i]);
        }

        // This is technically a noop with regards to the tokens' weights in storage. However, it performs important
        // validation of the token weights (normalization / bounds checking), and emits an event for offchain services.
        _startGradualWeightChange(
            block.timestamp,
            block.timestamp,
            params.normalizedWeights,
            params.normalizedWeights,
            params.tokens
        );

        _startGradualSwapFeeChange(
            block.timestamp,
            block.timestamp,
            params.swapFeePercentage,
            params.swapFeePercentage
        );

        // If false, the pool will start in the disabled state (prevents front-running the enable swaps transaction).
        _setSwapEnabled(params.swapEnabledOnStart);

        // If true, only addresses on the manager-controlled allowlist may join the pool.
        _setMustAllowlistLPs(params.mustAllowlistLPs);

        // Joins and exits are enabled by default on start.
        _setJoinExitEnabled(true);
    }

    function _getPoolState() internal view returns (bytes32) {
        return _poolState;
    }

    function _getTokenState(IERC20 token) internal view returns (bytes32) {
        return _tokenState[token];
    }

    function _getCircuitBreakerState(IERC20 token) internal view returns (bytes32) {
        return _circuitBreakerState[token];
    }

    // Virtual Supply

    /**
     * @notice Returns the number of tokens in circulation.
     * @dev For the majority of Pools, this will simply be a wrapper around the `totalSupply` function. However,
     * composable pools premint a large fraction of the BPT supply and place it in the Vault. In this situation,
     * the override would subtract this BPT balance from the total to reflect the actual amount of BPT in circulation.
     */
    function _getVirtualSupply() internal view virtual returns (uint256);

    // Actual Supply

    function getActualSupply() external view override returns (uint256) {
        return _getActualSupply(_getVirtualSupply());
    }

    function _getActualSupply(uint256 virtualSupply) internal view returns (uint256) {
        (uint256 aumFeePercentage, uint256 lastCollectionTimestamp) = getManagementAumFeeParams();
        uint256 aumFeesAmount = ExternalAUMFees.getAumFeesBptAmount(
            virtualSupply,
            block.timestamp,
            lastCollectionTimestamp,
            aumFeePercentage
        );
        return virtualSupply.add(aumFeesAmount);
    }

    // Swap fees

    /**
     * @notice Returns the current value of the swap fee percentage.
     * @dev Computes the current swap fee percentage, which can change every block if a gradual swap fee
     * update is in progress.
     */
    function getSwapFeePercentage() external view override returns (uint256) {
        return ManagedPoolStorageLib.getSwapFeePercentage(_poolState);
    }

    function getGradualSwapFeeUpdateParams()
        external
        view
        override
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 startSwapFeePercentage,
            uint256 endSwapFeePercentage
        )
    {
        return ManagedPoolStorageLib.getSwapFeeFields(_poolState);
    }

    function updateSwapFeeGradually(
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    ) external override authenticate whenNotPaused {
        _startGradualSwapFeeChange(
            GradualValueChange.resolveStartTime(startTime, endTime),
            endTime,
            startSwapFeePercentage,
            endSwapFeePercentage
        );
    }

    function _validateSwapFeePercentage(uint256 swapFeePercentage) internal pure {
        _require(swapFeePercentage >= _MIN_SWAP_FEE_PERCENTAGE, Errors.MIN_SWAP_FEE_PERCENTAGE);
        _require(swapFeePercentage <= _MAX_SWAP_FEE_PERCENTAGE, Errors.MAX_SWAP_FEE_PERCENTAGE);
    }

    /**
     * @notice Encodes a gradual swap fee update into the Pool state in storage.
     * @param startTime - The timestamp when the swap fee change will begin.
     * @param endTime - The timestamp when the swap fee change will end (must be >= startTime).
     * @param startSwapFeePercentage - The starting value for the swap fee change.
     * @param endSwapFeePercentage - The ending value for the swap fee change. If the current timestamp >= endTime,
     * `getSwapFeePercentage()` will return this value.
     */
    function _startGradualSwapFeeChange(
        uint256 startTime,
        uint256 endTime,
        uint256 startSwapFeePercentage,
        uint256 endSwapFeePercentage
    ) internal {
        _validateSwapFeePercentage(startSwapFeePercentage);
        _validateSwapFeePercentage(endSwapFeePercentage);

        _poolState = ManagedPoolStorageLib.setSwapFeeData(
            _poolState,
            startTime,
            endTime,
            startSwapFeePercentage,
            endSwapFeePercentage
        );

        emit GradualSwapFeeUpdateScheduled(startTime, endTime, startSwapFeePercentage, endSwapFeePercentage);
    }

    // Token weights

    /**
     * @dev Returns all normalized weights, in the same order as the Pool's tokens.
     */
    function _getNormalizedWeights(IERC20[] memory tokens) internal view returns (uint256[] memory normalizedWeights) {
        uint256 weightChangeProgress = ManagedPoolStorageLib.getGradualWeightChangeProgress(_poolState);

        uint256 numTokens = tokens.length;
        normalizedWeights = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            normalizedWeights[i] = ManagedPoolTokenStorageLib.getTokenWeight(
                _tokenState[tokens[i]],
                weightChangeProgress
            );
        }
    }

    function getNormalizedWeights() external view override returns (uint256[] memory) {
        (IERC20[] memory tokens, ) = _getPoolTokens();
        return _getNormalizedWeights(tokens);
    }

    /**
     * @dev Returns the normalized weight of a single token.
     */
    function _getNormalizedWeight(IERC20 token) internal view returns (uint256) {
        return
            ManagedPoolTokenStorageLib.getTokenWeight(
                _tokenState[token],
                ManagedPoolStorageLib.getGradualWeightChangeProgress(_poolState)
            );
    }

    function getGradualWeightUpdateParams()
        external
        view
        override
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256[] memory startWeights,
            uint256[] memory endWeights
        )
    {
        (startTime, endTime) = ManagedPoolStorageLib.getWeightChangeFields(_poolState);

        (IERC20[] memory tokens, ) = _getPoolTokens();

        startWeights = new uint256[](tokens.length);
        endWeights = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            (startWeights[i], endWeights[i]) = ManagedPoolTokenStorageLib.getTokenStartAndEndWeights(
                _tokenState[tokens[i]]
            );
        }
    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        IERC20[] memory tokens,
        uint256[] memory endWeights
    ) external override authenticate whenNotPaused {
        (IERC20[] memory actualTokens, ) = _getPoolTokens();
        InputHelpers.ensureInputLengthMatch(tokens.length, actualTokens.length, endWeights.length);

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            _require(actualTokens[i] == tokens[i], Errors.TOKENS_MISMATCH);
        }

        _startGradualWeightChange(
            GradualValueChange.resolveStartTime(startTime, endTime),
            endTime,
            _getNormalizedWeights(tokens),
            endWeights,
            tokens
        );
    }

    /**
     * @dev Validate the end weights, and set the start weights. `updateWeightsGradually` passes in the current weights
     * as the start weights, so that calling updateWeightsGradually again during an update will not result in any
     * abrupt weight changes. Also update the pool state with the start and end times.
     */
    function _startGradualWeightChange(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory startWeights,
        uint256[] memory endWeights,
        IERC20[] memory tokens
    ) internal {
        uint256 normalizedSum;

        for (uint256 i = 0; i < endWeights.length; i++) {
            uint256 endWeight = endWeights[i];
            // _require(endWeight >= WeightedMath._MIN_WEIGHT, Errors.MIN_WEIGHT);
            normalizedSum = normalizedSum.add(endWeight);

            IERC20 token = tokens[i];
            _tokenState[token] = ManagedPoolTokenStorageLib.setTokenWeight(
                _tokenState[token],
                startWeights[i],
                endWeight
            );
        }

        // Ensure that the normalized weights sum to ONE
        _require(normalizedSum == FixedPoint.ONE, Errors.NORMALIZED_WEIGHT_INVARIANT);

        _poolState = ManagedPoolStorageLib.setWeightChangeData(_poolState, startTime, endTime);

        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }

    // Join / Exit Enabled

    function getJoinExitEnabled() external view override returns (bool) {
        return ManagedPoolStorageLib.getJoinExitEnabled(_poolState);
    }

    function setJoinExitEnabled(bool joinExitEnabled) external override authenticate whenNotPaused {
        _setJoinExitEnabled(joinExitEnabled);
    }

    function _setJoinExitEnabled(bool joinExitEnabled) private {
        _poolState = ManagedPoolStorageLib.setJoinExitEnabled(_poolState, joinExitEnabled);

        emit JoinExitEnabledSet(joinExitEnabled);
    }

    // Swap Enabled

    function getSwapEnabled() external view override returns (bool) {
        return ManagedPoolStorageLib.getSwapEnabled(_poolState);
    }

    function setSwapEnabled(bool swapEnabled) external override authenticate whenNotPaused {
        _setSwapEnabled(swapEnabled);
    }

    function _setSwapEnabled(bool swapEnabled) private {
        _poolState = ManagedPoolStorageLib.setSwapEnabled(_poolState, swapEnabled);

        emit SwapEnabledSet(swapEnabled);
    }

    // LP Allowlist

    function getMustAllowlistLPs() external view override returns (bool) {
        return ManagedPoolStorageLib.getLPAllowlistEnabled(_poolState);
    }

    /**
     * @notice Check whether an LP address is on the allowlist.
     * @dev This simply checks the list, regardless of whether the allowlist feature is enabled, so that the allowlist
     * can be inspected at any time.
     * @param member - The address to check against the allowlist.
     * @return true if the given address is on the allowlist.
     */
    function isAddressOnAllowlist(address member) public view override returns (bool) {
        return _allowedAddresses[member];
    }

    /**
     * @notice Check an LP address against the allowlist.
     * @dev If the allowlist is not enabled, this returns true for every address.
     * @param poolState - The bytes32 representing the state of the pool.
     * @param member - The address to check against the allowlist.
     * @return - Whether the given address is allowed to join the pool.
     */
    function _isAllowedAddress(bytes32 poolState, address member) internal view returns (bool) {
        return !ManagedPoolStorageLib.getLPAllowlistEnabled(poolState) || isAddressOnAllowlist(member);
    }

    function addAllowedAddress(address member) external override authenticate whenNotPaused {
        _require(!isAddressOnAllowlist(member), Errors.ADDRESS_ALREADY_ALLOWLISTED);

        _allowedAddresses[member] = true;
        emit AllowlistAddressAdded(member);
    }

    function removeAllowedAddress(address member) external override authenticate whenNotPaused {
        _require(isAddressOnAllowlist(member), Errors.ADDRESS_NOT_ALLOWLISTED);

        delete _allowedAddresses[member];
        emit AllowlistAddressRemoved(member);
    }

    function setMustAllowlistLPs(bool mustAllowlistLPs) external override authenticate whenNotPaused {
        _setMustAllowlistLPs(mustAllowlistLPs);
    }

    function _setMustAllowlistLPs(bool mustAllowlistLPs) private {
        _poolState = ManagedPoolStorageLib.setLPAllowlistEnabled(_poolState, mustAllowlistLPs);

        emit MustAllowlistLPsSet(mustAllowlistLPs);
    }

    // AUM management fees

    function getManagementAumFeeParams()
        public
        view
        override
        returns (uint256 aumFeePercentage, uint256 lastCollectionTimestamp)
    {
        (aumFeePercentage, lastCollectionTimestamp) = ManagedPoolAumStorageLib.getAumFeeFields(_aumState);

        // If we're in recovery mode, set the fee percentage to zero so that we bypass any fee logic that might fail
        // and prevent LPs from exiting the pool.
        if (ManagedPoolStorageLib.getRecoveryModeEnabled(_poolState)) {
            aumFeePercentage = 0;
        }
    }

    function setManagementAumFeePercentage(uint256 managementAumFeePercentage)
        external
        override
        authenticate
        whenNotPaused
        returns (uint256 amount)
    {
        // We want to prevent the pool manager from retroactively increasing the amount of AUM fees payable.
        // To prevent this, we perform a collection before updating the fee percentage.
        // This is only necessary if the pool has been initialized (which is indicated by a nonzero total supply).
        uint256 supplyBeforeFeeCollection = _getVirtualSupply();
        if (supplyBeforeFeeCollection > 0) {
            amount = _collectAumManagementFees(supplyBeforeFeeCollection);
        }

        _setManagementAumFeePercentage(managementAumFeePercentage);
    }

    function _setManagementAumFeePercentage(uint256 managementAumFeePercentage) private {
        _require(
            managementAumFeePercentage <= _MAX_MANAGEMENT_AUM_FEE_PERCENTAGE,
            Errors.MAX_MANAGEMENT_AUM_FEE_PERCENTAGE
        );

        _aumState = ManagedPoolAumStorageLib.setAumFeePercentage(_aumState, managementAumFeePercentage);
        emit ManagementAumFeePercentageChanged(managementAumFeePercentage);
    }

    /**
     * @notice Stores the current timestamp as the most recent collection of AUM fees.
     * @dev This function *must* be called after each collection of AUM fees.
     */
    function _updateAumFeeCollectionTimestamp() internal {
        _aumState = ManagedPoolAumStorageLib.setLastCollectionTimestamp(_aumState, block.timestamp);
    }

    function collectAumManagementFees() external override whenNotPaused returns (uint256) {
        // It only makes sense to collect AUM fees after the pool is initialized (as before then the AUM is zero).
        // We can query if the pool is initialized by checking for a nonzero total supply.
        // Reverting here prevents zero value AUM fee collections causing bogus events.
        uint256 supply = _getVirtualSupply();
        _require(supply > 0, Errors.UNINITIALIZED);
        return _collectAumManagementFees(supply);
    }

    /**
     * @notice Calculates the AUM fees accrued since the last collection and pays it to the pool manager.
     * @dev The AUM fee calculation is based on inflating the Pool's BPT supply by a target rate. This assumes
     * a constant virtual supply between fee collections. To ensure proper accounting, we must therefore collect
     * AUM fees whenever the virtual supply of the Pool changes.
     *
     * This collection mints the difference between the virtual supply and the actual supply. By adding the amount of
     * BPT returned by this function to the virtual supply passed in, we may calculate the updated virtual supply
     * (which is equal to the actual supply).
     * @return bptAmount - The amount of BPT minted as AUM fees.
     */
    function _collectAumManagementFees(uint256 virtualSupply) internal returns (uint256) {
        (uint256 aumFeePercentage, uint256 lastCollectionTimestamp) = getManagementAumFeeParams();
        uint256 bptAmount = ExternalAUMFees.getAumFeesBptAmount(
            virtualSupply,
            block.timestamp,
            lastCollectionTimestamp,
            aumFeePercentage
        );

        // We always update last collection timestamp even when there is nothing to collect to ensure the state is kept
        // consistent.
        _updateAumFeeCollectionTimestamp();

        // Early return if either:
        // - AUM fee is disabled.
        // - no time has passed since the last collection.
        if (bptAmount == 0) {
            return 0;
        }

        // Split AUM fees between protocol and Pool manager. In low liquidity situations, rounding may result in a
        // managerBPTAmount of zero. In general, when splitting fees, LPs come first, followed by the protocol,
        // followed by the manager.
        // uint256 protocolBptAmount = bptAmount.mulUp(kickbackForBalancer);
        // uint256 managerBPTAmount = bptAmount.sub(protocolBptAmount);
        // _payProtocolFees(protocolBptAmount);

        emit ManagementAumFeeCollected(bptAmount);

        _mintPoolTokens(getOwner(), bptAmount);

        return bptAmount;
    }

    // Add/Remove tokens

    function addToken(
        IERC20 tokenToAdd,
        address assetManager,
        uint256 tokenToAddNormalizedWeight,
        uint256 mintAmount,
        address recipient
    ) external override authenticate whenNotPaused {
        {
            // This complex operation might mint BPT, altering the supply. For simplicity, we forbid adding tokens
            // before initialization (i.e. before BPT is first minted). We must also collect AUM fees every time the
            // BPT supply changes. For consistency, we do this always, even if the amount to mint is zero.
            uint256 supply = _getVirtualSupply();
            _require(supply > 0, Errors.UNINITIALIZED);
            _collectAumManagementFees(supply);
        }

        (IERC20[] memory tokens, ) = _getPoolTokens();
        _require(tokens.length + 1 <= _MAX_TOKENS, Errors.MAX_TOKENS);

        // `ManagedPoolAddRemoveTokenLib.addToken` performs any necessary state updates in the Vault and returns
        // values necessary for the Pool to update its own state.
        (bytes32 tokenToAddState, IERC20[] memory newTokens, uint256[] memory newWeights) = ManagedPoolAddRemoveTokenLib
            .addToken(
            getVault(),
            getPoolId(),
            _poolState,
            tokens,
            _getNormalizedWeights(tokens),
            tokenToAdd,
            assetManager,
            tokenToAddNormalizedWeight
        );

        // Once we've updated the state in the Vault, we also need to update our own state. This is a two-step process,
        // since we need to:
        //  a) initialize the state of the new token
        //  b) adjust the weights of all other tokens

        // Initializing the new token is straightforward. The Pool itself doesn't track how many or which tokens it uses
        // (and relies instead on the Vault for this), so we simply store the new token-specific information.
        // Note that we don't need to check here that the weight is valid. We'll later call `_startGradualWeightChange`,
        // which will check the entire set of weights for correctness.
        _tokenState[tokenToAdd] = tokenToAddState;

        // `_startGradualWeightChange` will perform all required validation on the new weights, including minimum
        // weights, sum, etc., so we don't need to worry about that ourselves.
        // Note that this call will set the weight for `tokenToAdd`, which we've already done - that'll just be a no-op.
        _startGradualWeightChange(block.timestamp, block.timestamp, newWeights, newWeights, newTokens);

        if (mintAmount > 0) {
            _mintPoolTokens(recipient, mintAmount);
        }

        emit TokenAdded(tokenToAdd, tokenToAddNormalizedWeight);
    }

    function removeToken(
        IERC20 tokenToRemove,
        uint256 burnAmount,
        address sender
    ) external override authenticate whenNotPaused {
        {
            // Add new scope to avoid stack too deep.

            // This complex operation might burn BPT, altering the supply. For simplicity, we forbid removing tokens
            // before initialization (i.e. before BPT is first minted). We must also collect AUM fees every time the
            // BPT supply changes. For consistency, we do this always, even if the amount to burn is zero.
            uint256 supply = _getVirtualSupply();
            _require(supply > 0, Errors.UNINITIALIZED);
            _collectAumManagementFees(supply);
        }

        (IERC20[] memory tokens, ) = _getPoolTokens();
        _require(tokens.length - 1 >= 2, Errors.MIN_TOKENS);

        // Token removal is forbidden during a weight change or if one is scheduled so we can assume that
        // the weight change progress is 100%.
        uint256 tokenToRemoveNormalizedWeight = ManagedPoolTokenStorageLib.getTokenWeight(
            _tokenState[tokenToRemove],
            FixedPoint.ONE
        );

        // `ManagedPoolAddRemoveTokenLib.removeToken` performs any necessary state updates in the Vault and returns
        // values necessary for the Pool to update its own state.
        (IERC20[] memory newTokens, uint256[] memory newWeights) = ManagedPoolAddRemoveTokenLib.removeToken(
            getVault(),
            getPoolId(),
            _poolState,
            tokens,
            _getNormalizedWeights(tokens),
            tokenToRemove,
            tokenToRemoveNormalizedWeight
        );

        // Once we've updated the state in the Vault, we also need to update our own state. This is a two-step process,
        // since we need to:
        //  a) delete the state of the removed token
        //  b) adjust the weights of all other tokens

        // Deleting the old token is straightforward. The Pool itself doesn't track how many or which tokens it uses
        // (and relies instead on the Vault for this), so we simply delete the token-specific information.
        delete _tokenState[tokenToRemove];

        // `_startGradualWeightChange` will perform all required validation on the new weights, including minimum
        // weights, sum, etc., so we don't need to worry about that ourselves.
        _startGradualWeightChange(block.timestamp, block.timestamp, newWeights, newWeights, newTokens);

        if (burnAmount > 0) {
            // We disallow burning from the zero address, as that would allow potentially returning the Pool to the
            // uninitialized state.
            _require(sender != address(0), Errors.BURN_FROM_ZERO);
            _burnPoolTokens(sender, burnAmount);
        }

        // The Pool is now again in a valid state: by the time the zero valued token is deregistered, all internal Pool
        // state is updated.

        emit TokenRemoved(tokenToRemove);
    }

    // Scaling Factors

    function getScalingFactors() external view override returns (uint256[] memory) {
        (IERC20[] memory tokens, ) = _getPoolTokens();
        return _scalingFactors(tokens);
    }

    function _scalingFactors(IERC20[] memory tokens) internal view returns (uint256[] memory scalingFactors) {
        uint256 numTokens = tokens.length;
        scalingFactors = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            scalingFactors[i] = ManagedPoolTokenStorageLib.getTokenScalingFactor(_tokenState[tokens[i]]);
        }
    }

    // Protocol Fee Cache

    /**
     * @dev Pays any due protocol and manager fees before updating the cached protocol fee percentages.
     */
    function _beforeProtocolFeeCacheUpdate() internal override {
        // We pay any due protocol or manager fees *before* updating the cache. This ensures that the new
        // percentages only affect future operation of the Pool, and not past fees.

        // Given that this operation is state-changing and relatively complex, we only allow it as long as the Pool is
        // not paused.
        _ensureNotPaused();

        // We skip fee collection until the Pool is initialized.
        uint256 supplyBeforeFeeCollection = _getVirtualSupply();
        if (supplyBeforeFeeCollection > 0) {
            _collectAumManagementFees(supplyBeforeFeeCollection);
        }
    }

    // Recovery Mode

    /**
     * @notice Returns whether the pool is in Recovery Mode.
     */
    function inRecoveryMode() public view override returns (bool) {
        return ManagedPoolStorageLib.getRecoveryModeEnabled(_poolState);
    }

    /**
     * @dev Sets the recoveryMode state, and emits the corresponding event.
     */
    function _setRecoveryMode(bool enabled) internal override {
        _poolState = ManagedPoolStorageLib.setRecoveryModeEnabled(_poolState, enabled);

        // Some pools need to update their state when leaving recovery mode to ensure proper functioning of the Pool.
        // We do not perform any state updates when entering recovery mode, as this may jeopardize the ability to
        // enable Recovery mode.
        if (!enabled) {
            // Recovery mode exits bypass the AUM fee calculation. This means that if the Pool is paused and in
            // Recovery mode for a period of time, then later returns to normal operation, AUM fees will be charged
            // to the remaining LPs for the full period. We then update the collection timestamp so that no AUM fees
            // are accrued over this period.
            _updateAumFeeCollectionTimestamp();
        }
    }

    // Circuit Breakers

    function getCircuitBreakerState(IERC20 token)
        external
        view
        override
        returns (
            uint256 bptPrice,
            uint256 referenceWeight,
            uint256 lowerBound,
            uint256 upperBound,
            uint256 lowerBptPriceBound,
            uint256 upperBptPriceBound
        )
    {
        bytes32 circuitBreakerState = _circuitBreakerState[token];

        (bptPrice, referenceWeight, lowerBound, upperBound) = CircuitBreakerStorageLib.getCircuitBreakerFields(
            circuitBreakerState
        );

        uint256 normalizedWeight = _getNormalizedWeight(token);

        lowerBptPriceBound = CircuitBreakerStorageLib.getBptPriceBound(circuitBreakerState, normalizedWeight, true);
        upperBptPriceBound = CircuitBreakerStorageLib.getBptPriceBound(circuitBreakerState, normalizedWeight, false);

        // Restore the original unscaled BPT price passed in `setCircuitBreakers`.
        uint256 tokenScalingFactor = ManagedPoolTokenStorageLib.getTokenScalingFactor(_getTokenState(token));
        bptPrice = _upscale(bptPrice, tokenScalingFactor);

        // Also render the adjusted bounds as unscaled values.
        lowerBptPriceBound = _upscale(lowerBptPriceBound, tokenScalingFactor);
        upperBptPriceBound = _upscale(upperBptPriceBound, tokenScalingFactor);
    }

    function setCircuitBreakers(
        IERC20[] memory tokens,
        uint256[] memory bptPrices,
        uint256[] memory lowerBoundPercentages,
        uint256[] memory upperBoundPercentages
    ) external override authenticate whenNotPaused {
        InputHelpers.ensureInputLengthMatch(tokens.length, lowerBoundPercentages.length, upperBoundPercentages.length);
        InputHelpers.ensureInputLengthMatch(tokens.length, bptPrices.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            _setCircuitBreaker(tokens[i], bptPrices[i], lowerBoundPercentages[i], upperBoundPercentages[i]);
        }
    }

    // Compute the reference values, then pass them along with the bounds to the library. The bptPrice must be
    // passed in from the caller, or it would be manipulable. We assume the bptPrice from the caller was computed
    // using the native (i.e., unscaled) token balance.
    function _setCircuitBreaker(
        IERC20 token,
        uint256 bptPrice,
        uint256 lowerBoundPercentage,
        uint256 upperBoundPercentage
    ) private {
        uint256 normalizedWeight = _getNormalizedWeight(token);
        // Fail if the token is not in the pool (or is the BPT token)
        _require(normalizedWeight != 0, Errors.INVALID_TOKEN);

        // The incoming BPT price (defined as actualSupply * weight / balance) will have been calculated dividing
        // by unscaled token balance, effectively multiplying the result by the scaling factor.
        // To correct this, we need to divide by it (downscaling).
        uint256 scaledBptPrice = _downscaleDown(
            bptPrice,
            ManagedPoolTokenStorageLib.getTokenScalingFactor(_getTokenState(token))
        );

        // The library will validate the lower/upper bounds
        _circuitBreakerState[token] = CircuitBreakerStorageLib.setCircuitBreaker(
            scaledBptPrice,
            normalizedWeight,
            lowerBoundPercentage,
            upperBoundPercentage
        );

        // Echo the unscaled BPT price in the event.
        emit CircuitBreakerSet(token, bptPrice, lowerBoundPercentage, upperBoundPercentage);
    }

    // Misc

    /**
     * @dev Enumerates all ownerOnly functions in Managed Pool.
     */
    function _isOwnerOnlyAction(bytes32 actionId) internal view override returns (bool) {
        return
            (actionId == getActionId(ManagedPoolSettings.updateWeightsGradually.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.updateSwapFeeGradually.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.setJoinExitEnabled.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.setSwapEnabled.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.addAllowedAddress.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.removeAllowedAddress.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.setMustAllowlistLPs.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.addToken.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.removeToken.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.setManagementAumFeePercentage.selector)) ||
            (actionId == getActionId(ManagedPoolSettings.setCircuitBreakers.selector));
    }

    /**
     * @notice Returns the tokens in the Pool and their current balances.
     * @dev This function must be overridden to process these arrays according to the specific pool type.
     * A common example of this is in composable pools, as we may need to drop the BPT token and its balance.
     */
    function _getPoolTokens() internal view virtual returns (IERC20[] memory tokens, uint256[] memory balances);
}

/**
 * @title Managed Pool
 * @dev Weighted Pool with mutable tokens and weights, designed to be used in conjunction with a contract
 * (as the owner, containing any specific business logic). Since the pool itself permits "dangerous"
 * operations, it should never be deployed with an EOA as the owner.
 *
 * The owner contract can impose arbitrary access control schemes on its permissions: it might allow a multisig
 * to add or remove tokens, and let an EOA set the swap fees.
 *
 * Pool owners can also serve as intermediate contracts to hold tokens, deploy timelocks, consult with
 * other protocols or on-chain oracles, or bundle several operations into one transaction that re-entrancy
 * protection would prevent initiating from the pool contract.
 *
 * Managed Pools are designed to support many asset management use cases, including: large token counts,
 * rebalancing through token changes, gradual weight or fee updates, fine-grained control of protocol and
 * management fees, allowlisting of LPs, and more.
 */
contract JBManagedPool is IVersion, ManagedPoolSettings {
    // ManagedPool weights and swap fees can change over time: these periods are expected to be long enough (e.g. days)
    // that any timestamp manipulation would achieve very little.
    // solhint-disable not-rely-on-time

    using FixedPoint for uint256;
    using BasePoolUserData for bytes;
    using WeightedPoolUserData for bytes;

    // The maximum imposed by the Vault, which stores balances in a packed format, is 2**(112) - 1.
    // We are only minting half of the maximum value - already an amount many orders of magnitude greater than any
    // conceivable real liquidity - to allow for minting new BPT as a result of regular joins.
    uint256 private constant _PREMINTED_TOKEN_BALANCE = 2**(111);
    IExternalWeightedMath private immutable _weightedMath;
    string private _version;

    struct ManagedPoolParams {
        string name;
        string symbol;
        address[] assetManagers;
    }

    struct ManagedPoolConfigParams {
        IVault vault;
        IProtocolFeePercentagesProvider protocolFeeProvider;
        IExternalWeightedMath weightedMath;
        uint256 pauseWindowDuration;
        uint256 bufferPeriodDuration;
        string version;
    }

    constructor(
        ManagedPoolParams memory params,
        ManagedPoolConfigParams memory configParams,
        ManagedPoolSettingsParams memory settingsParams,
        address owner
    )
        NewBasePool(
            configParams.vault,
            PoolRegistrationLib.registerComposablePool(
                configParams.vault,
                IVault.PoolSpecialization.MINIMAL_SWAP_INFO,
                settingsParams.tokens,
                params.assetManagers
            ),
            params.name,
            params.symbol,
            configParams.pauseWindowDuration,
            configParams.bufferPeriodDuration,
            owner
        )
        ManagedPoolSettings(settingsParams, configParams.protocolFeeProvider)
    {   
        _weightedMath = configParams.weightedMath;
        _version = configParams.version;
    }

    function version() external view override returns (string memory) {
        return _version;
    }

    function _getWeightedMath() internal view returns (IExternalWeightedMath) {
        return _weightedMath;
    }

    // Virtual Supply

    /**
     * @notice Returns the number of tokens in circulation.
     * @dev In other pools, this would be the same as `totalSupply`, but since this pool pre-mints BPT and holds it in
     * the Vault as a token, we need to subtract the Vault's balance to get the total "circulating supply". Both the
     * totalSupply and Vault balance can change. If users join or exit using swaps, some of the preminted BPT are
     * exchanged, so the Vault's balance increases after joins and decreases after exits. If users call the recovery
     * mode exit function, the totalSupply can change as BPT are burned.
     *
     * The virtual supply can also be calculated by calling ComposablePoolLib.dropBptFromBalances with appropriate
     * inputs, which is the preferred approach whenever possible, as it avoids extra calls to the Vault.
     */
    function _getVirtualSupply() internal view override returns (uint256) {
        (uint256 cash, uint256 managed, , ) = getVault().getPoolTokenInfo(getPoolId(), IERC20(this));
        // We don't need to use SafeMath here as the Vault restricts token balances to be less than 2**112.
        // This ensures that `cash + managed` cannot overflow and the Pool's balance of BPT cannot exceed the total
        // supply so we cannot underflow either.
        return totalSupply() - (cash + managed);
    }

    // Swap Hooks

    /**
     * @dev Dispatch code for all kinds of swaps. Depending on the tokens involved this could result in a join, exit or
     * a standard swap between two token in the Pool.
     *
     * The return value is expected to be downscaled (appropriately rounded based on the swap type) ready to be passed
     * to the Vault.
     */
    function _onSwapMinimal(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    ) internal override returns (uint256) {
        bytes32 poolState = _getPoolState();

        // ManagedPool is a composable Pool, so a swap could be either a join swap, an exit swap, or a token swap.
        // By checking whether the incoming or outgoing token is the BPT, we can determine which kind of
        // operation we want to perform and pass it to the appropriate handler.
        //
        // We block all types of swap if swaps are disabled as a token swap is equivalent to a join swap followed by
        // an exit swap into a different token.
        _require(ManagedPoolStorageLib.getSwapEnabled(poolState), Errors.SWAPS_DISABLED);

        if (request.tokenOut == IERC20(this)) {
            // `tokenOut` is the BPT, so this is a join swap.

            // Check allowlist for LPs, if applicable
            _require(_isAllowedAddress(poolState, request.from), Errors.ADDRESS_NOT_ALLOWLISTED);

            // This is equivalent to `_getVirtualSupply()`, but as `balanceTokenOut` is the Vault's balance of BPT
            // we can avoid querying this value again from the Vault as we do in `_getVirtualSupply()`.
            uint256 virtualSupply = totalSupply() - balanceTokenOut;

            // See documentation for `getActualSupply()` and `_collectAumManagementFees()`.
            uint256 actualSupply = virtualSupply + _collectAumManagementFees(virtualSupply);

            return _onJoinSwap(request, balanceTokenIn, actualSupply, poolState);
        } else if (request.tokenIn == IERC20(this)) {
            // `tokenIn` is the BPT, so this is an exit swap.

            // Note that we do not check the LP allowlist here. LPs must always be able to exit the pool,
            // and enforcing the allowlist would allow the manager to perform DOS attacks on LPs.

            // This is equivalent to `_getVirtualSupply()`, but as `balanceTokenIn` is the Vault's balance of BPT
            // we can avoid querying this value again from the Vault as we do in `_getVirtualSupply()`.
            uint256 virtualSupply = totalSupply() - balanceTokenIn;

            // See documentation for `getActualSupply()` and `_collectAumManagementFees()`.
            uint256 actualSupply = virtualSupply + _collectAumManagementFees(virtualSupply);

            return _onExitSwap(request, balanceTokenOut, actualSupply, poolState);
        } else {
            // Neither token is the BPT, so this is a standard token swap.
            return _onTokenSwap(request, balanceTokenIn, balanceTokenOut, poolState);
        }
    }

    /*
     * @dev Called when a swap with the Pool occurs, where the tokens leaving the Pool are BPT.
     *
     * This function is responsible for upscaling any amounts received, in particular `balanceTokenIn`
     * and `request.amount`.
     *
     * The return value is expected to be downscaled (appropriately rounded based on the swap type) ready to be passed
     * to the Vault.
     */
    function _onJoinSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 actualSupply,
        bytes32 poolState
    ) internal view returns (uint256) {
        // Check whether joins are enabled.
        _require(ManagedPoolStorageLib.getJoinExitEnabled(poolState), Errors.JOINS_EXITS_DISABLED);

        // We first query data needed to perform the joinswap, i.e. the token weight and scaling factor as well as the
        // Pool's swap fee.
        (uint256 tokenInWeight, uint256 scalingFactorTokenIn) = _getTokenInfo(
            request.tokenIn,
            ManagedPoolStorageLib.getGradualWeightChangeProgress(poolState)
        );
        uint256 swapFeePercentage = ManagedPoolStorageLib.getSwapFeePercentage(poolState);

        // `_onSwapMinimal` passes unscaled values so we upscale the token balance.
        balanceTokenIn = _upscale(balanceTokenIn, scalingFactorTokenIn);

        // We may also need to upscale `request.amount`, however we do not yet know this as that depends on whether that
        // is a token amount (GIVEN_IN) or a BPT amount (GIVEN_OUT), which gets no scaling.
        //
        // Therefore we branch depending on the swap kind and calculate the `bptAmountOut` for GIVEN_IN joinswaps or the
        // `amountIn` for GIVEN_OUT joinswaps. We call these values the `amountCalculated`.
        uint256 amountCalculated;
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // In `GIVEN_IN` joinswaps, `request.amount` is the amount of tokens entering the pool so we upscale with
            // `scalingFactorTokenIn`.
            request.amount = _upscale(request.amount, scalingFactorTokenIn);

            // Once fees are removed we can then calculate the equivalent BPT amount.
            amountCalculated = _getWeightedMath().calcBptOutGivenExactTokenIn(
                balanceTokenIn,
                tokenInWeight,
                request.amount,
                actualSupply,
                swapFeePercentage
            );
        } else {
            // In `GIVEN_OUT` joinswaps, `request.amount` is the amount of BPT leaving the pool, which does not need any
            // scaling.
            amountCalculated = _getWeightedMath().calcTokenInGivenExactBptOut(
                balanceTokenIn,
                tokenInWeight,
                request.amount,
                actualSupply,
                swapFeePercentage
            );
        }

        // A joinswap decreases the price of the token entering the Pool and increases the price of all other tokens.
        // ManagedPool's circuit breakers prevent the tokens' prices from leaving certain bounds so we must  check that
        // we haven't tripped a breaker as a result of the joinswap.
        _checkCircuitBreakersOnJoinOrExitSwap(request, actualSupply, amountCalculated, true);

        // Finally we downscale `amountCalculated` before we return it.
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // BPT is leaving the Pool, which doesn't need scaling.
            return amountCalculated;
        } else {
            // `amountCalculated` tokens are entering the Pool, so we round up.
            return _downscaleUp(amountCalculated, scalingFactorTokenIn);
        }
    }

    /*
     * @dev Called when a swap with the Pool occurs, where the tokens entering the Pool are BPT.
     *
     * This function is responsible for upscaling any amounts received, in particular `balanceTokenOut`
     * and `request.amount`.
     *
     * The return value is expected to be downscaled (appropriately rounded based on the swap type) ready to be passed
     * to the Vault.
     */
    function _onExitSwap(
        SwapRequest memory request,
        uint256 balanceTokenOut,
        uint256 actualSupply,
        bytes32 poolState
    ) internal view returns (uint256) {
        // Check whether exits are enabled.
        _require(ManagedPoolStorageLib.getJoinExitEnabled(poolState), Errors.JOINS_EXITS_DISABLED);

        // We first query data needed to perform the exitswap, i.e. the token weight and scaling factor as well as the
        // Pool's swap fee.
        (uint256 tokenOutWeight, uint256 scalingFactorTokenOut) = _getTokenInfo(
            request.tokenOut,
            ManagedPoolStorageLib.getGradualWeightChangeProgress(poolState)
        );
        uint256 swapFeePercentage = ManagedPoolStorageLib.getSwapFeePercentage(poolState);

        // `_onSwapMinimal` passes unscaled values so we upscale the token balance.
        balanceTokenOut = _upscale(balanceTokenOut, scalingFactorTokenOut);

        // We may also need to upscale `request.amount`, however we do not yet know this as that depends on whether that
        // is a BPT amount (GIVEN_IN), which gets no scaling, or a token amount (GIVEN_OUT).
        //
        // Therefore we branch depending on the swap kind and calculate the `amountOut` for GIVEN_IN exitswaps or the
        // `bptAmountIn` for GIVEN_OUT exitswaps. We call these values the `amountCalculated`.
        uint256 amountCalculated;
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // In `GIVEN_IN` exitswaps, `request.amount` is the amount of BPT entering the pool, which does not need any
            // scaling.
            amountCalculated = _getWeightedMath().calcTokenOutGivenExactBptIn(
                balanceTokenOut,
                tokenOutWeight,
                request.amount,
                actualSupply,
                swapFeePercentage
            );
        } else {
            // In `GIVEN_OUT` exitswaps, `request.amount` is the amount of tokens leaving the pool so we upscale with
            // `scalingFactorTokenOut`.
            request.amount = _upscale(request.amount, scalingFactorTokenOut);

            amountCalculated = _getWeightedMath().calcBptInGivenExactTokenOut(
                balanceTokenOut,
                tokenOutWeight,
                request.amount,
                actualSupply,
                swapFeePercentage
            );
        }

        // A exitswap increases the price of the token leaving the Pool and decreases the price of all other tokens.
        // ManagedPool's circuit breakers prevent the tokens' prices from leaving certain bounds so we must  check that
        // we haven't tripped a breaker as a result of the exitswap.
        _checkCircuitBreakersOnJoinOrExitSwap(request, actualSupply, amountCalculated, false);

        // Finally we downscale `amountCalculated` before we return it.
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // `amountCalculated` tokens are exiting the Pool, so we round down.
            return _downscaleDown(amountCalculated, scalingFactorTokenOut);
        } else {
            // BPT is entering the Pool, which doesn't need scaling.
            return amountCalculated;
        }
    }

    // Holds information for the tokens involved in a regular swap.
    struct SwapTokenData {
        uint256 tokenInWeight;
        uint256 tokenOutWeight;
        uint256 scalingFactorTokenIn;
        uint256 scalingFactorTokenOut;
    }

    /*
     * @dev Called when a swap with the Pool occurs, where neither of the tokens involved are the BPT of the Pool.
     *
     * This function is responsible for upscaling any amounts received, in particular `balanceTokenIn`,
     * `balanceTokenOut` and `request.amount`.
     *
     * The return value is expected to be downscaled (appropriately rounded based on the swap type) ready to be passed
     * to the Vault.
     */
    function _onTokenSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut,
        bytes32 poolState
    ) internal view returns (uint256) {
        // We first query data needed to perform the swap, i.e. token weights and scaling factors as well as the Pool's
        // swap fee (in the form of its complement).
        SwapTokenData memory tokenData = _getSwapTokenData(request, poolState);
        uint256 swapFeeComplement = ManagedPoolStorageLib.getSwapFeePercentage(poolState).complement();

        // `_onSwapMinimal` passes unscaled values so we upscale token balances using the appropriate scaling factors.
        balanceTokenIn = _upscale(balanceTokenIn, tokenData.scalingFactorTokenIn);
        balanceTokenOut = _upscale(balanceTokenOut, tokenData.scalingFactorTokenOut);

        // We must also upscale `request.amount` however we do not yet know which scaling factor to use as this differs
        // depending on whether it represents an amount of tokens entering (GIVEN_IN) or leaving (GIVEN_OUT) the Pool.
        //
        // Therefore we branch depending on the swap kind and calculate the `amountOut` for GIVEN_IN swaps or the
        // `amountIn` for GIVEN_OUT swaps. We call these values the `amountCalculated`.
        uint256 amountCalculated;
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // In `GIVEN_IN` swaps, `request.amount` is the amount of tokens entering the pool so we upscale with
            // `scalingFactorTokenIn`.
            request.amount = _upscale(request.amount, tokenData.scalingFactorTokenIn);

            // We then subtract swap fees from this amount so the collected swap fees aren't use to calculate how many
            // tokens the trader will receive. We round this value down (favoring a higher fee amount).
            uint256 amountInMinusFees = request.amount.mulDown(swapFeeComplement);

            // Once fees are removed we can then calculate the equivalent amount of `tokenOut`.
            amountCalculated = _getWeightedMath().calcOutGivenIn(
                balanceTokenIn,
                tokenData.tokenInWeight,
                balanceTokenOut,
                tokenData.tokenOutWeight,
                amountInMinusFees
            );
        } else {
            // In `GIVEN_OUT` swaps, `request.amount` is the amount of tokens leaving the pool so we upscale with
            // `scalingFactorTokenOut`.
            request.amount = _upscale(request.amount, tokenData.scalingFactorTokenOut);

            // We first calculate how many tokens must be sent in order to receive `request.amount` tokens out.
            // This calculation does not yet include fees.
            uint256 amountInMinusFees = _getWeightedMath().calcInGivenOut(
                balanceTokenIn,
                tokenData.tokenInWeight,
                balanceTokenOut,
                tokenData.tokenOutWeight,
                request.amount
            );

            // We then add swap fees to this amount so the trader must send extra tokens.
            // We round this value up (favoring a higher fee amount).
            amountCalculated = amountInMinusFees.divUp(swapFeeComplement);
        }

        // A token swap increases the price of the token leaving the Pool and reduces the price of the token entering
        // the Pool. ManagedPool's circuit breakers prevent the tokens' prices from leaving certain bounds so we must
        // check that we haven't tripped a breaker as a result of the token swap.
        _checkCircuitBreakersOnRegularSwap(request, tokenData, balanceTokenIn, balanceTokenOut, amountCalculated);

        // Finally we downscale `amountCalculated` before we return it. We want to round this value in favour of the
        // Pool so apply different scaling on amounts entering or leaving the Pool.
        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // `amountCalculated` tokens are exiting the Pool, so we round down.
            return _downscaleDown(amountCalculated, tokenData.scalingFactorTokenOut);
        } else {
            // `amountCalculated` tokens are entering the Pool, so we round up.
            return _downscaleUp(amountCalculated, tokenData.scalingFactorTokenIn);
        }
    }

    /**
     * @dev Gather the information required to process a regular token swap. This is required to avoid stack-too-deep
     * issues.
     */
    function _getSwapTokenData(SwapRequest memory request, bytes32 poolState)
        private
        view
        returns (SwapTokenData memory tokenInfo)
    {
        bytes32 tokenInState = _getTokenState(request.tokenIn);
        bytes32 tokenOutState = _getTokenState(request.tokenOut);

        uint256 weightChangeProgress = ManagedPoolStorageLib.getGradualWeightChangeProgress(poolState);
        tokenInfo.tokenInWeight = ManagedPoolTokenStorageLib.getTokenWeight(tokenInState, weightChangeProgress);
        tokenInfo.tokenOutWeight = ManagedPoolTokenStorageLib.getTokenWeight(tokenOutState, weightChangeProgress);

        tokenInfo.scalingFactorTokenIn = ManagedPoolTokenStorageLib.getTokenScalingFactor(tokenInState);
        tokenInfo.scalingFactorTokenOut = ManagedPoolTokenStorageLib.getTokenScalingFactor(tokenOutState);
    }

    /**
     * @notice Returns a token's weight and scaling factor
     */
    function _getTokenInfo(IERC20 token, uint256 weightChangeProgress)
        private
        view
        returns (uint256 tokenWeight, uint256 scalingFactor)
    {
        bytes32 tokenState = _getTokenState(token);
        tokenWeight = ManagedPoolTokenStorageLib.getTokenWeight(tokenState, weightChangeProgress);
        scalingFactor = ManagedPoolTokenStorageLib.getTokenScalingFactor(tokenState);
    }

    // Initialize

    function _onInitializePool(
        address sender,
        address,
        bytes memory userData
    ) internal override returns (uint256 bptAmountOut, uint256[] memory amountsIn) {
        // Check allowlist for LPs, if applicable
        _require(_isAllowedAddress(_getPoolState(), sender), Errors.ADDRESS_NOT_ALLOWLISTED);

        // Ensure that the user intends to initialize the Pool.
        WeightedPoolUserData.JoinKind kind = userData.joinKind();
        _require(kind == WeightedPoolUserData.JoinKind.INIT, Errors.UNINITIALIZED);

        // Extract the initial token balances `sender` is sending to the Pool.
        (IERC20[] memory tokens, ) = _getPoolTokens();
        amountsIn = userData.initialAmountsIn();
        InputHelpers.ensureInputLengthMatch(amountsIn.length, tokens.length);

        // We now want to determine the correct amount of BPT to mint in return for these tokens.
        // In order to do this we calculate the Pool's invariant which requires the token amounts to be upscaled.
        uint256[] memory scalingFactors = _scalingFactors(tokens);
        _upscaleArray(amountsIn, scalingFactors);

        uint256 invariantAfterJoin = _getWeightedMath().calculateInvariant(_getNormalizedWeights(tokens), amountsIn);

        // Set the initial BPT to the value of the invariant times the number of tokens. This makes BPT supply more
        // consistent in Pools with similar compositions but different number of tokens.
        bptAmountOut = Math.mul(invariantAfterJoin, amountsIn.length);

        // We don't need upscaled balances anymore and will need to return downscaled amounts so we downscale here.
        // `amountsIn` are amounts entering the Pool, so we round up when doing this.
        _downscaleUpArray(amountsIn, scalingFactors);

        // BasePool will mint `bptAmountOut` for the sender: we then also mint the remaining BPT to make up the total
        // supply, and have the Vault pull those tokens from the sender as part of the join.
        //
        // Note that the sender need not approve BPT for the Vault as the Vault already has infinite BPT allowance for
        // all accounts.
        uint256 initialBpt = _PREMINTED_TOKEN_BALANCE.sub(bptAmountOut);
        _mintPoolTokens(sender, initialBpt);

        // The Vault expects an array of amounts which includes BPT (which always sits in the first position).
        // We then add an extra element to the beginning of the array and set it to `initialBpt`.
        amountsIn = ComposablePoolLib.prependZeroElement(amountsIn);
        amountsIn[0] = initialBpt;

        // At this point we have all necessary return values for the initialization.

        // Finally, we want to start collecting AUM fees from this point onwards. Prior to initialization the Pool holds
        // no funds so naturally charges no AUM fees.
        _updateAumFeeCollectionTimestamp();
    }

    // Join

    function _onJoinPool(
        address sender,
        uint256[] memory balances,
        bytes memory userData
    ) internal virtual override returns (uint256 bptAmountOut, uint256[] memory amountsIn) {
        // The Vault passes an array of balances which includes the pool's BPT (This always sits in the first position).
        // We want to separate this from the other balances before continuing with the join.
        uint256 virtualSupply;
        (virtualSupply, balances) = ComposablePoolLib.dropBptFromBalances(totalSupply(), balances);

        // We want to upscale all of the balances received from the Vault by the appropriate scaling factors.
        // In order to do this we must query the Pool's tokens from the Vault as ManagedPool doesn't keep track.
        (IERC20[] memory tokens, ) = _getPoolTokens();
        uint256[] memory scalingFactors = _scalingFactors(tokens);
        _upscaleArray(balances, scalingFactors);

        // See documentation for `getActualSupply()` and `_collectAumManagementFees()`.
        uint256 actualSupply = virtualSupply + _collectAumManagementFees(virtualSupply);
        uint256[] memory normalizedWeights = _getNormalizedWeights(tokens);

        (bptAmountOut, amountsIn) = _doJoin(
            sender,
            balances,
            normalizedWeights,
            scalingFactors,
            actualSupply,
            userData
        );

        _checkCircuitBreakers(actualSupply.add(bptAmountOut), tokens, balances, amountsIn, normalizedWeights, true);

        // amountsIn are amounts entering the Pool, so we round up.
        _downscaleUpArray(amountsIn, scalingFactors);

        // The Vault expects an array of amounts which includes BPT so prepend an empty element to this array.
        amountsIn = ComposablePoolLib.prependZeroElement(amountsIn);
    }

    /**
     * @dev Dispatch code which decodes the provided userdata to perform the specified join type.
     */
    function _doJoin(
        address sender,
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory scalingFactors,
        uint256 totalSupply,
        bytes memory userData
    ) internal view returns (uint256, uint256[] memory) {
        bytes32 poolState = _getPoolState();

        // Check whether joins are enabled.
        _require(ManagedPoolStorageLib.getJoinExitEnabled(poolState), Errors.JOINS_EXITS_DISABLED);

        WeightedPoolUserData.JoinKind kind = userData.joinKind();

        // If swaps are disabled, only proportional joins are allowed. All others involve implicit swaps, and alter
        // token prices.
        _require(
            ManagedPoolStorageLib.getSwapEnabled(poolState) ||
                kind == WeightedPoolUserData.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
            Errors.INVALID_JOIN_EXIT_KIND_WHILE_SWAPS_DISABLED
        );

        // Check allowlist for LPs, if applicable
        _require(_isAllowedAddress(poolState, sender), Errors.ADDRESS_NOT_ALLOWLISTED);

        if (kind == WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            return
                _getWeightedMath().joinExactTokensInForBPTOut(
                    balances,
                    normalizedWeights,
                    scalingFactors,
                    totalSupply,
                    ManagedPoolStorageLib.getSwapFeePercentage(poolState),
                    userData
                );
        } else if (kind == WeightedPoolUserData.JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT) {
            return
                _getWeightedMath().joinTokenInForExactBPTOut(
                    balances,
                    normalizedWeights,
                    totalSupply,
                    ManagedPoolStorageLib.getSwapFeePercentage(poolState),
                    userData
                );
        } else if (kind == WeightedPoolUserData.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT) {
            return _getWeightedMath().joinAllTokensInForExactBPTOut(balances, totalSupply, userData);
        } else {
            _revert(Errors.UNHANDLED_JOIN_KIND);
        }
    }

    // Exit

    function _onExitPool(
        address sender,
        uint256[] memory balances,
        bytes memory userData
    ) internal virtual override returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        // The Vault passes an array of balances which includes the pool's BPT (This always sits in the first position).
        // We want to separate this from the other balances before continuing with the exit.
        uint256 virtualSupply;
        (virtualSupply, balances) = ComposablePoolLib.dropBptFromBalances(totalSupply(), balances);

        // We want to upscale all of the balances received from the Vault by the appropriate scaling factors.
        // In order to do this we must query the Pool's tokens from the Vault as ManagedPool doesn't keep track.
        (IERC20[] memory tokens, ) = _getPoolTokens();
        uint256[] memory scalingFactors = _scalingFactors(tokens);
        _upscaleArray(balances, scalingFactors);

        // See documentation for `getActualSupply()` and `_collectAumManagementFees()`.
        uint256 actualSupply = virtualSupply + _collectAumManagementFees(virtualSupply);

        uint256[] memory normalizedWeights = _getNormalizedWeights(tokens);

        (bptAmountIn, amountsOut) = _doExit(
            sender,
            balances,
            normalizedWeights,
            scalingFactors,
            actualSupply,
            userData
        );

        // Do not check circuit breakers on proportional exits, which do not change BPT prices.
        if (userData.exitKind() != WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            _checkCircuitBreakers(
                actualSupply.sub(bptAmountIn),
                tokens,
                balances,
                amountsOut,
                normalizedWeights,
                false
            );
        }

        // amountsOut are amounts exiting the Pool, so we round down.
        _downscaleDownArray(amountsOut, scalingFactors);

        // The Vault expects an array of amounts which includes BPT so prepend an empty element to this array.
        amountsOut = ComposablePoolLib.prependZeroElement(amountsOut);
    }

    /**
     * @dev Dispatch code which decodes the provided userdata to perform the specified exit type.
     * Inheriting contracts may override this function to add additional exit types or extra conditions to allow
     * or disallow exit under certain circumstances.
     */
    function _doExit(
        address,
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256[] memory scalingFactors,
        uint256 totalSupply,
        bytes memory userData
    ) internal view virtual returns (uint256, uint256[] memory) {
        bytes32 poolState = _getPoolState();

        // Check whether exits are enabled. Recovery mode exits are not blocked by this check, since they are routed
        // through a different codepath at the base pool layer.
        _require(ManagedPoolStorageLib.getJoinExitEnabled(poolState), Errors.JOINS_EXITS_DISABLED);

        WeightedPoolUserData.ExitKind kind = userData.exitKind();

        // If swaps are disabled, only proportional exits are allowed. All others involve implicit swaps, and alter
        // token prices.
        _require(
            ManagedPoolStorageLib.getSwapEnabled(poolState) ||
                kind == WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            Errors.INVALID_JOIN_EXIT_KIND_WHILE_SWAPS_DISABLED
        );

        // Note that we do not check the LP allowlist here. LPs must always be able to exit the pool,
        // and enforcing the allowlist would allow the manager to perform DOS attacks on LPs.

        if (kind == WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) {
            return
                _getWeightedMath().exitExactBPTInForTokenOut(
                    balances,
                    normalizedWeights,
                    totalSupply,
                    ManagedPoolStorageLib.getSwapFeePercentage(poolState),
                    userData
                );
        } else if (kind == WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
            return _getWeightedMath().exitExactBPTInForTokensOut(balances, totalSupply, userData);
        } else if (kind == WeightedPoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT) {
            return
                _getWeightedMath().exitBPTInForExactTokensOut(
                    balances,
                    normalizedWeights,
                    scalingFactors,
                    totalSupply,
                    ManagedPoolStorageLib.getSwapFeePercentage(poolState),
                    userData
                );
        } else {
            _revert(Errors.UNHANDLED_EXIT_KIND);
        }
    }

    // function _doRecoveryModeExit(
    //     uint256[] memory balances,
    //     uint256 totalSupply,
    //     bytes memory userData
    // ) internal pure override returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
    //     // As ManagedPool is a composable Pool, `_doRecoveryModeExit()` must use the virtual supply rather than the
    //     // total supply to correctly distribute Pool assets proportionally.
    //     // We must also ensure that we do not pay out a proportionaly fraction of the BPT held in the Vault, otherwise
    //     // this would allow a user to recursively exit the pool using BPT they received from the previous exit.

    //     uint256 virtualSupply;
    //     (virtualSupply, balances) = ComposablePoolLib.dropBptFromBalances(totalSupply, balances);

    //     bptAmountIn = userData.recoveryModeExit();
    //     amountsOut = BasePoolMath.computeProportionalAmountsOut(balances, virtualSupply, bptAmountIn);

    //     // The Vault expects an array of amounts which includes BPT so prepend an empty element to this array.
    //     amountsOut = ComposablePoolLib.prependZeroElement(amountsOut);
    // }

    /**
     * @notice Returns the tokens in the Pool and their current balances.
     * @dev This function drops the BPT token and its balance from the returned arrays as these values are unused by
     * internal functions outside of the swap/join/exit hooks.
     */
    function _getPoolTokens() internal view override returns (IERC20[] memory, uint256[] memory) {
        (IERC20[] memory registeredTokens, uint256[] memory registeredBalances, ) = getVault().getPoolTokens(
            getPoolId()
        );
        return ComposablePoolLib.dropBpt(registeredTokens, registeredBalances);
    }

    // Circuit Breakers

    // Depending on the type of operation, we may need to check only the upper or lower bound, or both.
    enum BoundCheckKind { LOWER, UPPER, BOTH }

    /**
     * @dev Check the circuit breakers of the two tokens involved in a regular swap.
     */
    function _checkCircuitBreakersOnRegularSwap(
        SwapRequest memory request,
        SwapTokenData memory tokenData,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut,
        uint256 amountCalculated
    ) private view {
        uint256 actualSupply = _getActualSupply(_getVirtualSupply());

        (uint256 amountIn, uint256 amountOut) = request.kind == IVault.SwapKind.GIVEN_IN
            ? (request.amount, amountCalculated)
            : (amountCalculated, request.amount);

        // Since the balance of tokenIn is increasing, its BPT price will decrease,
        // so we need to check the lower bound.
        _checkCircuitBreaker(
            BoundCheckKind.LOWER,
            request.tokenIn,
            actualSupply,
            balanceTokenIn.add(amountIn),
            tokenData.tokenInWeight
        );

        // Since the balance of tokenOut is decreasing, its BPT price will increase,
        // so we need to check the upper bound.
        _checkCircuitBreaker(
            BoundCheckKind.UPPER,
            request.tokenOut,
            actualSupply,
            balanceTokenOut.sub(amountOut),
            tokenData.tokenOutWeight
        );
    }

    /**
     * @dev We need to check the breakers for all tokens on joins and exits (including join and exit swaps), since any
     * change to the BPT supply affects all BPT prices. For a multi-token join or exit, we will have a set of
     * balances and amounts. For a join/exitSwap, only one token balance is changing. We can use the same data for
     *  both: in the single token swap case, the other token `amounts` will be zero.
     */
    function _checkCircuitBreakersOnJoinOrExitSwap(
        SwapRequest memory request,
        uint256 actualSupply,
        uint256 amountCalculated,
        bool isJoin
    ) private view {
        uint256 newActualSupply;
        uint256 amount;

        // This is a swap between the BPT token and another pool token. Calculate the end state: actualSupply
        // and the token amount being swapped, depending on whether it is a join or exit, GivenIn or GivenOut.
        if (isJoin) {
            (newActualSupply, amount) = request.kind == IVault.SwapKind.GIVEN_IN
                ? (actualSupply.add(amountCalculated), request.amount)
                : (actualSupply.add(request.amount), amountCalculated);
        } else {
            (newActualSupply, amount) = request.kind == IVault.SwapKind.GIVEN_IN
                ? (actualSupply.sub(request.amount), amountCalculated)
                : (actualSupply.sub(amountCalculated), request.amount);
        }

        // Since this is a swap, we do not have all the tokens, balances, or weights, and need to fetch them.
        (IERC20[] memory tokens, uint256[] memory balances) = _getPoolTokens();
        uint256[] memory normalizedWeights = _getNormalizedWeights(tokens);
        _upscaleArray(balances, _scalingFactors(tokens));

        // Initialize to all zeros, and set the amount associated with the swap.
        uint256[] memory amounts = new uint256[](tokens.length);
        IERC20 token = isJoin ? request.tokenIn : request.tokenOut;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                amounts[i] = amount;
                break;
            }
        }

        _checkCircuitBreakers(newActualSupply, tokens, balances, amounts, normalizedWeights, isJoin);
    }

    /**
     * @dev Check circuit breakers for a set of tokens. The given virtual supply is what it will be post-operation:
     * this includes any pending external fees, and the amount of BPT exchanged (swapped, minted, or burned) in the
     * current operation.
     *
     * We pass in the tokens, upscaled balances, and weights necessary to compute BPT prices, then check the circuit
     * breakers. Unlike a straightforward token swap, where we know the direction the BPT price will move, once the
     * virtual supply changes, all bets are off. To be safe, we need to check both directions for all tokens.
     *
     * It does attempt to short circuit quickly if there is no bound set.
     */
    function _checkCircuitBreakers(
        uint256 actualSupply,
        IERC20[] memory tokens,
        uint256[] memory balances,
        uint256[] memory amounts,
        uint256[] memory normalizedWeights,
        bool isJoin
    ) private view {
        for (uint256 i = 0; i < balances.length; i++) {
            uint256 finalBalance = (isJoin ? FixedPoint.add : FixedPoint.sub)(balances[i], amounts[i]);

            // Since we cannot be sure which direction the BPT price of the token has moved,
            // we must check both the lower and upper bounds.
            _checkCircuitBreaker(BoundCheckKind.BOTH, tokens[i], actualSupply, finalBalance, normalizedWeights[i]);
        }
    }

    // Check the appropriate circuit breaker(s) according to the BoundCheckKind.
    function _checkCircuitBreaker(
        BoundCheckKind checkKind,
        IERC20 token,
        uint256 actualSupply,
        uint256 balance,
        uint256 weight
    ) private view {
        bytes32 circuitBreakerState = _getCircuitBreakerState(token);

        if (checkKind == BoundCheckKind.LOWER || checkKind == BoundCheckKind.BOTH) {
            _checkOneSidedCircuitBreaker(circuitBreakerState, actualSupply, balance, weight, true);
        }

        if (checkKind == BoundCheckKind.UPPER || checkKind == BoundCheckKind.BOTH) {
            _checkOneSidedCircuitBreaker(circuitBreakerState, actualSupply, balance, weight, false);
        }
    }

    // Check either the lower or upper bound circuit breaker for the given token.
    function _checkOneSidedCircuitBreaker(
        bytes32 circuitBreakerState,
        uint256 actualSupply,
        uint256 balance,
        uint256 weight,
        bool isLowerBound
    ) private pure {
        uint256 bound = CircuitBreakerStorageLib.getBptPriceBound(circuitBreakerState, weight, isLowerBound);

        _require(
            !CircuitBreakerLib.hasCircuitBreakerTripped(actualSupply, weight, balance, bound, isLowerBound),
            Errors.CIRCUIT_BREAKER_TRIPPED
        );
    }

    // Unimplemented

    /**
     * @dev Unimplemented as ManagedPool uses the MinimalInfoSwap Pool specialization.
     */
    function _onSwapGeneral(
        SwapRequest memory, /*request*/
        uint256[] memory, /* balances*/
        uint256, /* indexIn */
        uint256 /*indexOut */
    ) internal pure override returns (uint256) {
        _revert(Errors.UNIMPLEMENTED);
    }
}

