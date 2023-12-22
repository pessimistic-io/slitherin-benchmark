// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IDeFiBridgeState.sol";

interface IDeFiBridgeEvents {
  event WalletSetup(address wallet);
  event BridgeSetup(address wormhole, address relayer);
  event ChainAdded(uint16 indexed chain, address pool, address token, bool active);
  event ChainUpdated(uint16 indexed chain, address pool, address token, bool active);
  event Deposited(bytes indexed msgHash, uint16 toChain, address indexed recipient, uint256 amount);
  event Withdrawn(bytes indexed msgHash, uint16 fromChain, address indexed recipient, uint256 amount);
  event FeesSetup(uint256 nativeFee, uint256 tokenFee);
  event ERC20Recovered(address token, uint256 amount);
  event NativeRecovered(uint256 amount);
}
