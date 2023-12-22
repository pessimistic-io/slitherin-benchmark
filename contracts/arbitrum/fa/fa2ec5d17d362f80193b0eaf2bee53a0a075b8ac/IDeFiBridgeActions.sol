// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IDeFiBridgeState.sol";

interface IDeFiBridgeActions {
  /**
   * @dev Setups new wallet.
   * @param wallet_  new wallet address.
   */
  function setupWallet(address wallet_) external;

  /**
   * @dev Setups new bridge messaging.
   * @param chain_  chain id.
   * @param wormhole_  new wormhole address.
   * @param relayer_  new relayer address.
   */
  function setupBridge(uint16 chain_, address wormhole_, address relayer_) external;
  
  /**
   * @dev Setups new fees.
   * @param nativeFee_  new native coin fee(absolute).
   * @param tokenFee_  new token fee(percent).
   * @param minTokenFee_  new min token fee.
   * @param maxTokenFee_  new max token fee.
   */
  function setupFees(uint256 nativeFee_, uint256 tokenFee_, uint256 minTokenFee_, uint256 maxTokenFee_) external;
  
  /**
   * @dev Setups new chains to bridge.
   * @param chain_  global chain id.
   * @param pool_  bridge pool address.
   * @param defi_  defi token address.
   */
  function setupChain(uint16 chain_, address pool_, address defi_) external;
  
  /**
   * @dev Enables chains to bridge.
   * @param chain_  global chain id.
   */
  function enableChain(uint16 chain_) external;
  
  /**
   * @dev Disables chains to bridge.
   * @param chain_  global chain id.
   */
  function disableChain(uint16 chain_) external;
  
  /**
   * @dev Bridges tokens.
   * @param chain_  global chain id.
   * @param recipient_  address who will receive tokens.
   * @param amount_  amount of tokens to bridge.
   */
  function bridge(uint16 chain_, address recipient_, uint256 amount_) external payable returns (bytes memory msgHash);
  
  /**
   * @dev Recovers native coins.
   */
  function recoverNative() external;
  
  /**
   * @dev Recovers erc20 tokens.
   * @param token_  token address to recover.
   * @param amount_  token amounts to recover.
   */
  function recoverERC20(address token_, uint256 amount_) external;
  
  /**
   * @dev Returns calculated fees for bridge transactions.
   * @param chain_  global chain id.
   * @param amount_  amount of tokens to bridge.
   */
  function getFees(uint16 chain_, uint256 amount_) external view returns (uint256 nativeCost, uint256 tokenCost);
  
  /**
   * @dev Returns chain info.
   * @param chain_  global chain id.
   */
  function getChain(uint16 chain_) external view returns(IDeFiBridgeState.Chain memory);

  /**
   * @dev Returns all fees parameters.
   */
  function getFeesInfo() external view returns(uint256 nativeFee, uint256 tokenFee, uint256 minTokenFee, uint256 maxTokenFee);

  /**
   * @dev Returns wallet address
   */
  function getWallet() external view returns(address);
}
