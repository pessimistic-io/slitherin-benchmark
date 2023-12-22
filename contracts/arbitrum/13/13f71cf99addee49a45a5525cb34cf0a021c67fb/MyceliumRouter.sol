// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IMyceliumRouter.sol";

contract MyceliumRouter is
  IMyceliumRouter,
  Initializable,
  OwnableUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public constant VERSION = 1;
  address public activeRouter;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address router) public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    __ReentrancyGuard_init();
    activeRouter = router;
  }

  function swap(bytes calldata forwardedCallData) external payable nonReentrant {
    OneInchSwapDescription memory swapDesc = parseData(forwardedCallData);

    if (swapDesc.dstReceiver != msg.sender) revert Unauthorized();

    IERC20Upgradeable(swapDesc.srcToken).safeTransferFrom(msg.sender, address(this), swapDesc.amount);

    (bool success, bytes memory result) = activeRouter.call{ value: msg.value }(forwardedCallData);
    if (!success) revert SwapFailed();

    uint256 returnAmount = getReturnAmount(result);

    emit SwapSuccess(
      swapDesc.dstReceiver,
      address(swapDesc.srcToken),
      address(swapDesc.dstToken),
      swapDesc.amount,
      swapDesc.minReturnAmount,
      returnAmount
    );
  }

  function parseData(bytes calldata data) public pure returns (OneInchSwapDescription memory swapDesc) {
    (, swapDesc, ) = abi.decode(data[4:], (address, OneInchSwapDescription, bytes));
  }

  function getReturnAmount(bytes memory result) public pure returns (uint256 returnAmount) {
    (returnAmount, ) = abi.decode(result, (uint256, uint256));
  }

  /**
   * Set new router.
   */
  function setRouter(address newRouter) external onlyOwner {
    if (newRouter == address(0)) revert ZeroAddress();
    emit RouterUpdated(newRouter, activeRouter);
    activeRouter = newRouter;
  }

  /**
   * Approve active router to spend tokens in array.
   */
  function approveRouterSpend(IERC20Upgradeable[] calldata tokens) external onlyOwner {
    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].approve(activeRouter, type(uint256).max);
    }
  }

  /**
   * Revoke spender approval for tokens in array.
   */
  function revokeSpend(IERC20Upgradeable[] calldata tokens, address spender) external onlyOwner {
    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].approve(spender, 0);
    }
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

