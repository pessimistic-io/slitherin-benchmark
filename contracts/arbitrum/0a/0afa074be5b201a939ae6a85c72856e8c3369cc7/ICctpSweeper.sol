// SPDX-License-Identifier: MIT

pragma solidity >=0.8.21;

import {IERC20} from "./IERC20.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";

/**
 * @title Sweep an address's USDC balance to another chain via Circle's CCTP Bridge
 * @author Warbler Labs Engineering
 * @notice The destination chain is set during initialization
 */
interface ICctpSweeper {
  function usdc() external view returns (IERC20);

  /**
   * @notice Circle's TokenMessenger contract, the entrypoint to the bridge. See full list by chain:
   * https://developers.circle.com/stablecoins/docs/cctp-protocol-contract#tokenmessenger-mainnet
   */
  function tokenMessenger() external view returns (ITokenMessenger);

  /**
   * @notice The "domain" of the destination chain
   * See https://developers.circle.com/stablecoins/docs/cctp-technical-reference#domain
   */
  function destinationDomain() external view returns (uint32);

  /**
   * @notice Move all USDC from `addr` to the CCTP Bridge with Base as the destination chain. This
   * contract must be USDC approved by `addr` before sweeping.
   * @param addr address whose USDC to sweep
   */
  function sweep(address addr) external;

  /**
   * Emitted on a successful sweep to Cctp
   * @param addr address whose USDC was sweeped. Also the receiving address on Base
   * @param amount amount that was sweeped
   */
  event Swept(address indexed addr, uint256 amount);

  /**
   * Thrown when the sweeper is not approved for an amount greater than or equal to the
   * user's current balance.
   */
  error InsufficientAllowance(address addr);
}

