// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma experimental ABIEncoderV2;

import "./IAsset.sol";
import "./ERC20.sol";

pragma solidity >=0.7.0 <0.9.0;

/**
 * @dev Stripped version of `@balancer-labs/v2-interfaces/contracts/vault/IVault.sol`
 * that only exposes the necessary vault methods for DepositTradeHelper.
 */
interface IVault {
  /**
   * @dev Returns a Pool's registered tokens, the total balance for each, and the latest block when *any* of
   * the tokens' `balances` changed.
   *
   * The order of the `tokens` array is the same order that will be used in `joinPool`, `exitPool`, as well as in all
   * Pool hooks (where applicable). Calls to `registerTokens` and `deregisterTokens` may change this order.
   *
   * If a Pool only registers tokens once, and these are sorted in ascending order, they will be stored in the same
   * order as passed to `registerTokens`.
   *
   * Total balances include both tokens held by the Vault and those withdrawn by the Pool's Asset Managers. These are
   * the amounts used by joins, exits and swaps. For a detailed breakdown of token balances, use `getPoolTokenInfo`
   * instead.
   */
  function getPoolTokens(bytes32 poolId)
    external
    view
    returns (
      IERC20[] memory tokens,
      uint256[] memory balances,
      uint256 lastChangeBlock
    );

  // Swaps
  //
  // Users can swap tokens with Pools by calling the `swap` and `batchSwap` functions. To do this,
  // they need not trust Pool contracts in any way: all security checks are made by the Vault. They must however be
  // aware of the Pools' pricing algorithms in order to estimate the prices Pools will quote.
  //
  // The `swap` function executes a single swap, while `batchSwap` can perform multiple swaps in sequence.
  // In each individual swap, tokens of one kind are sent from the sender to the Pool (this is the 'token in'),
  // and tokens of another kind are sent from the Pool to the recipient in exchange (this is the 'token out').
  // More complex swaps, such as one token in to multiple tokens out can be achieved by batching together
  // individual swaps.
  //
  // There are two swap kinds:
  //  - 'given in' swaps, where the amount of tokens in (sent to the Pool) is known, and the Pool determines (via the
  // `onSwap` hook) the amount of tokens out (to send to the recipient).
  //  - 'given out' swaps, where the amount of tokens out (received from the Pool) is known, and the Pool determines
  // (via the `onSwap` hook) the amount of tokens in (to receive from the sender).
  //
  // Additionally, it is possible to chain swaps using a placeholder input amount, which the Vault replaces with
  // the calculated output of the previous swap. If the previous swap was 'given in', this will be the calculated
  // tokenOut amount. If the previous swap was 'given out', it will use the calculated tokenIn amount. These extended
  // swaps are known as 'multihop' swaps, since they 'hop' through a number of intermediate tokens before arriving at
  // the final intended token.
  //
  // In all cases, tokens are only transferred in and out of the Vault (or withdrawn from and deposited into Internal
  // Balance) after all individual swaps have been completed, and the net token balance change computed. This makes
  // certain swap patterns, such as multihops, or swaps that interact with the same token pair in multiple Pools, cost
  // much less gas than they would otherwise.
  //
  // It also means that under certain conditions it is possible to perform arbitrage by swapping with multiple
  // Pools in a way that results in net token movement out of the Vault (profit), with no tokens being sent in (only
  // updating the Pool's internal accounting).
  //
  // To protect users from front-running or the market changing rapidly, they supply a list of 'limits' for each token
  // involved in the swap, where either the maximum number of tokens to send (by passing a positive value) or the
  // minimum amount of tokens to receive (by passing a negative value) is specified.
  //
  // Additionally, a 'deadline' timestamp can also be provided, forcing the swap to fail if it occurs after
  // this point in time (e.g. if the transaction failed to be included in a block promptly).
  //
  // If interacting with Pools that hold WETH, it is possible to both send and receive ETH directly: the Vault will do
  // the wrapping and unwrapping. To enable this mechanism, the IAsset sentinel value (the zero address) must be
  // passed in the `assets` array instead of the WETH address. Note that it is possible to combine ETH and WETH in the
  // same swap. Any excess ETH will be sent back to the caller (not the sender, which is relevant for relayers).
  //
  // Finally, Internal Balance can be used when either sending or receiving tokens.

  enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
  }

  /**
   * @dev Performs a swap with a single Pool.
   *
   * If the swap is 'given in' (the number of tokens to send to the Pool is known), it returns the amount of tokens
   * taken from the Pool, which must be greater than or equal to `limit`.
   *
   * If the swap is 'given out' (the number of tokens to take from the Pool is known), it returns the amount of tokens
   * sent to the Pool, which must be less than or equal to `limit`.
   *
   * Internal Balance usage and the recipient are determined by the `funds` struct.
   *
   * Emits a `Swap` event.
   */
  function swap(
    SingleSwap memory singleSwap,
    FundManagement memory funds,
    uint256 limit,
    uint256 deadline
  ) external payable returns (uint256);

  /**
   * @dev Data for a single swap executed by `swap`. `amount` is either `amountIn` or `amountOut` depending on
   * the `kind` value.
   *
   * `assetIn` and `assetOut` are either token addresses, or the IAsset sentinel value for ETH (the zero address).
   * Note that Pools never interact with ETH directly: it will be wrapped to or unwrapped from WETH by the Vault.
   *
   * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
   * used to extend swap behavior.
   */
  struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    IAsset assetIn;
    IAsset assetOut;
    uint256 amount;
    bytes userData;
  }

  /**
   * @dev Data for each individual swap executed by `batchSwap`. The asset in and out fields are indexes into the
   * `assets` array passed to that function, and ETH assets are converted to WETH.
   *
   * If `amount` is zero, the multihop mechanism is used to determine the actual amount based on the amount in/out
   * from the previous swap, depending on the swap kind.
   *
   * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
   * used to extend swap behavior.
   */
  struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
  }

  /**
   * @dev All tokens in a swap are either sent from the `sender` account to the Vault, or from the Vault to the
   * `recipient` account.
   *
   * If the caller is not `sender`, it must be an authorized relayer for them.
   *
   * If `fromInternalBalance` is true, the `sender`'s Internal Balance will be preferred, performing an ERC20
   * transfer for the difference between the requested amount and the User's Internal Balance (if any). The `sender`
   * must have allowed the Vault to use their tokens via `IERC20.approve()`. This matches the behavior of
   * `joinPool`.
   *
   * If `toInternalBalance` is true, tokens will be deposited to `recipient`'s internal balance instead of
   * transferred. This matches the behavior of `exitPool`.
   *
   * Note that ETH cannot be deposited to or withdrawn from Internal Balance: attempting to do so will trigger a
   * revert.
   */
  struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
  }

  /**
   * @dev Simulates a call to `batchSwap`, returning an array of Vault asset deltas. Calls to `swap` cannot be
   * simulated directly, but an equivalent `batchSwap` call can and will yield the exact same result.
   *
   * Each element in the array corresponds to the asset at the same index, and indicates the number of tokens (or ETH)
   * the Vault would take from the sender (if positive) or send to the recipient (if negative). The arguments it
   * receives are the same that an equivalent `batchSwap` call would receive.
   *
   * Unlike `batchSwap`, this function performs no checks on the sender or recipient field in the `funds` struct.
   * This makes it suitable to be called by off-chain applications via eth_call without needing to hold tokens,
   * approve them for the Vault, or even know a user's address.
   *
   * Note that this function is not 'view' (due to implementation details): the client code must explicitly execute
   * eth_call instead of eth_sendTransaction.
   */
  function queryBatchSwap(
    SwapKind kind,
    BatchSwapStep[] memory swaps,
    IAsset[] memory assets,
    FundManagement memory funds
  ) external returns (int256[] memory assetDeltas);
}

