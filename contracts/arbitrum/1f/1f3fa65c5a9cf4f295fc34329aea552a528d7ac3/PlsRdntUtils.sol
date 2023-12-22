// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import { IProtocolRewardsHandler, IMultiFeeDistribution } from "./Radiant.sol";
import { IRdntLpStaker, IPlsRdntUtils, IAToken } from "./Interfaces.sol";

contract PlsRdntUtils is IPlsRdntUtils {
  uint private constant FEE_DIVISOR = 1e4;
  IRdntLpStaker public constant STAKER = IRdntLpStaker(0x2A2CAFbB239af9159AEecC34AC25521DBd8B5197);
  IMultiFeeDistribution public constant MFD = IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);

  /**
   * @notice Replacement for MFD.claimableRewards with configurable tokens
   * @param _account address to query
   * @param _tokens reward tokens to query. Has to be present in mfd and be rToken
   * @return _rewardsData RewardData{address token, uint amount}[]
   */
  function mfdClaimableRewards(
    address _account,
    address[] memory _tokens
  ) public view returns (IProtocolRewardsHandler.RewardData[] memory _rewardsData) {
    _rewardsData = new IMultiFeeDistribution.RewardData[](_tokens.length);
    uint _lockedBalWithMultiplier;

    unchecked {
      // workaround because lockedBalWithMultiplier is not exposed
      _lockedBalWithMultiplier = MFD.totalBalance(_account) * 25;
    }

    for (uint i; i < _tokens.length; i = _unsafeInc(i)) {
      _rewardsData[i].token = _tokens[i];

      uint _earnings = MFD.rewards(_account, _rewardsData[i].token);

      unchecked {
        uint realRPT = MFD.rewardPerToken(_rewardsData[i].token) -
          MFD.userRewardPerTokenPaid(_account, _rewardsData[i].token);
        _earnings += (_lockedBalWithMultiplier * realRPT) / 1e18;
        _rewardsData[i].amount = _earnings / 1e12;
      }
    }
  }

  /**
   * @notice Claimable rdnt protocol rewards in underlying tokens for plutus dLP staker, after fees
   * @param _user address to query
   * @param _feeInBp fee in BP. default 1200.
   * @param _inUnderlyingAsset return RewardData token in underlying asset if true, else return rToken address
   * @return _pendingRewardsLessFee RewardData{address token, uint amount}[] with a length equal to RewardTokenCount(). Amount may be 0.
   */
  function pendingRewardsLessFee(
    address _user,
    uint _feeInBp,
    bool _inUnderlyingAsset
  ) external view returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewardsLessFee) {
    _pendingRewardsLessFee = mfdClaimableRewards(_user, STAKER.getRewardTokens());

    for (uint i; i < _pendingRewardsLessFee.length; i = _unsafeInc(i)) {
      if (_inUnderlyingAsset) {
        _pendingRewardsLessFee[i].token = IAToken(_pendingRewardsLessFee[i].token).UNDERLYING_ASSET_ADDRESS();
      }

      uint _amount = _pendingRewardsLessFee[i].amount;
      if (_amount > 0) {
        unchecked {
          _pendingRewardsLessFee[i].amount = _amount - ((_amount * _feeInBp) / FEE_DIVISOR);
        }
      }
    }
  }

  function _unsafeInc(uint x) private pure returns (uint) {
    unchecked {
      return x + 1;
    }
  }
}

