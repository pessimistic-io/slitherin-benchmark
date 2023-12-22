// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";

import "./ITokenAdapter.sol";

import "./IMiniChefV2.sol";

import { TokenUtils } from "./TokenUtils.sol";
import "./Checker.sol";

import "./IWrappedStakedJonesToken.sol";

/// @title  JonesDAOTokenAdapterWithArbRewards (for only USDC)
/// @dev Arbitrum provided JonesDAO a temporary grant to boost APRs.
/// This adapter allows Savvy to capture this extra emitted Arb.
/// @author Savvy DeFi
contract JonesDAOTokenAdapterWithArbRewards is
  ITokenAdapter,
  Initializable,
  Ownable2StepUpgradeable
{
  string public constant override version = "1.0.0";

  /// @notice Only SavvyPositionManager can call functions.
  mapping(address => bool) private isAllowlisted;

  address public override token; // wrapped stake token
  address public override baseToken;
  address private rewardToken;
  IWrappedStakedJonesToken public wrappedStakedJonesToken;

  modifier onlyAllowlist() {
    require(isAllowlisted[msg.sender], "Only Allowlist");
    _;
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address _wrappedStakedStargateToken) public initializer {
    Checker.checkArgument(
      _wrappedStakedStargateToken != address(0),
      "_wrappedStakedStargateToken cannot be 0 address"
    );

    wrappedStakedJonesToken = IWrappedStakedJonesToken(
      _wrappedStakedStargateToken
    );
    token = _wrappedStakedStargateToken;
    baseToken = wrappedStakedJonesToken.baseToken();
    rewardToken = wrappedStakedJonesToken.rewardToken();

    __Ownable2Step_init();
  }

  /// @inheritdoc ITokenAdapter
  function price() external view override returns (uint256) {
    return wrappedStakedJonesToken.price();
  }

  /// @inheritdoc ITokenAdapter
  function addAllowlist(
    address[] memory allowlistAddresses,
    bool status
  ) external override onlyOwner {
    require(allowlistAddresses.length > 0, "invalid length");
    for (uint256 i = 0; i < allowlistAddresses.length; i++) {
      isAllowlisted[allowlistAddresses[i]] = status;
    }
  }

  function getArbRewards() external onlyAllowlist returns (uint256) {
    wrappedStakedJonesToken.claim();
    uint256 rewardTokenBalance = TokenUtils.safeBalanceOf(
      rewardToken,
      address(this)
    );
    TokenUtils.safeTransfer(rewardToken, msg.sender, rewardTokenBalance);
    uint256 rewardTokenBalanceAfter = TokenUtils.safeBalanceOf(
      rewardToken,
      address(this)
    );
    require(rewardTokenBalanceAfter == 0, "Didn't transfer all rewardToken");
    return rewardTokenBalance;
  }

  /// @inheritdoc ITokenAdapter
  function wrap(
    uint256 amount,
    address recipient
  ) public override onlyAllowlist returns (uint256) {
    amount = TokenUtils.safeTransferFrom(
      baseToken,
      msg.sender,
      address(this),
      amount
    );
    Checker.checkArgument(amount > 0, "zero wrap amount");
    TokenUtils.safeApprove(baseToken, address(wrappedStakedJonesToken), amount);
    return wrappedStakedJonesToken.deposit(amount, recipient);
  }

  /// @inheritdoc ITokenAdapter
  function unwrap(
    uint256 amount,
    address recipient
  ) external override onlyAllowlist returns (uint256) {
    Checker.checkArgument(amount > 0, "zero unwrap amount");
    amount = TokenUtils.safeTransferFrom(
      token,
      msg.sender,
      address(this),
      amount
    );
    TokenUtils.safeApprove(token, address(wrappedStakedJonesToken), amount);
    uint256 baseTokenAmountWithdrawn = wrappedStakedJonesToken.withdraw(
      amount,
      address(this)
    );
    TokenUtils.safeTransfer(baseToken, recipient, baseTokenAmountWithdrawn);
    return baseTokenAmountWithdrawn;
  }

  receive() external payable {}

  uint256[100] private __gap;
}

