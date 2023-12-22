// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;
import "./IERC20.sol";
import { IProtocolRewardsHandler } from "./Radiant.sol";

interface IPlsRdntRewardsDistro {
  function sendRewards(address _to, IProtocolRewardsHandler.RewardData[] memory _pendingRewardAmounts) external;

  function record() external returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewards);

  function pendingRewards() external view returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewards);

  function lastHandled() external view returns (uint);

  event FeeChanged(uint256 indexed _new, uint256 _old);
  event HandleClaim(IProtocolRewardsHandler.RewardData[] _rewardsData);

  error UNAUTHORIZED();
  error INVALID_FEE();
}

interface IPlsRdntUtils {
  function mfdClaimableRewards(
    address _account,
    address[] memory _tokens
  ) external view returns (IProtocolRewardsHandler.RewardData[] memory _rewardsData);

  function pendingRewardsLessFee(
    address _user,
    uint _feeInBp,
    bool _inUnderlyingAsset
  ) external view returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewardsLessFee);
}

interface IRdntLpStaker {
  function stake(uint256) external;

  function getRewardTokens() external view returns (address[] memory);

  function getRewardTokenCount() external view returns (uint);

  function claimRadiantProtocolFees(
    address _to
  ) external returns (IProtocolRewardsHandler.RewardData[] memory _rewardsData);
}

interface IAToken is IERC20 {
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface IPlutusChef {
  function depositFor(address _user, uint96 _amount) external;
}

interface ITokenMinter {
  function mint(address, uint256) external;

  function burn(address, uint256) external;
}

interface IDelegation {
  function setDelegate(bytes32 id, address delegate) external;
}

interface IPlsRdntPlutusChef is IPlutusChef {
  error DEPOSIT_ERROR(string);
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();
  error FAILED(string);

  event HandlerUpdated(address indexed _handler, bool _isActive);
  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}

