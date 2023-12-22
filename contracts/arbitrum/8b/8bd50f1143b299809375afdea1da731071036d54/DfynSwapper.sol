// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";

contract DfynSwapper is AccessControl, ReentrancyGuard {
  using SafeERC20 for IERC20;
  IERC20 public constant ROUTER_DFYN =
    IERC20(0x13538f1450Ca2E1882Df650F87Eb996fF4Ffec34);

  IERC20 public constant ARBITRUM_DFYN =
    IERC20(0x1D54Aa7E322e02A0453c0F2fA21505cE7F2E9E93);

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  function deposit(uint256 amount) external nonReentrant {
    ARBITRUM_DFYN.transferFrom(msg.sender, address(this), amount);
    ROUTER_DFYN.transfer(msg.sender, amount);
  }

  function routeDfynBalance() external view returns (uint256) {
    return ROUTER_DFYN.balanceOf(address(this));
  }

  function arbitrumDfynBalance() external view returns (uint256) {
    return ARBITRUM_DFYN.balanceOf(address(this));
  }

  function withdrawRouterDfyn(uint256 amount, address recipient)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _withdraw(ROUTER_DFYN, amount, recipient);
  }

  function withdrawOtherDfyn(uint256 amount, address recipient)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _withdraw(ARBITRUM_DFYN, amount, recipient);
  }

  function withdrawAnyToken(
    IERC20 token,
    uint256 amount,
    address recipient
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _withdraw(token, amount, recipient);
  }

  function _withdraw(
    IERC20 token,
    uint256 amount,
    address recipient
  ) private {
    token.transfer(recipient, amount);
  }

  function withdrawNativeToken(uint256 amount, address payable recipient)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    (bool sent, ) = recipient.call{ value: amount }("");
    require(sent, "Transaction failed");
  }
}

