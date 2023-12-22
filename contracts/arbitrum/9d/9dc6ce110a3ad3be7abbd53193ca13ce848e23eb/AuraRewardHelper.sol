// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "./Ownable.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";

interface IBoosterLite {
  function poolInfo(
    uint256 _pid
  )
    external
    view
    returns (address lpToken, address token, address gauge, address crvRewards, address stash, bool shutdown);

  function earmarkRewards(uint256 _pid, address _zroPaymentAddress) external payable returns (bool);

  function crv() external view returns (address);
}

interface IBaseRewardPool {
  function periodFinish() external view returns (uint);
}

interface IRewardStash {
  function tokenInfo(address token) external view returns (address _token, address _rewardAddress, address _stashToken);
}

contract AuraRewardHelper is Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  struct RewardDetails {
    address from;
    uint96 ratePerWeek;
  }

  IBoosterLite public constant AURA_BOOSTER_LITE = IBoosterLite(0x98Ef32edd24e2c92525E59afc4475C1242a30184);
  IRewardStash public constant REWARD_STASH = IRewardStash(0xbF07300F92D56b805E4355e419c42D2EB99f71b8);
  uint256 public constant PID = 40;

  EnumerableSet.AddressSet private tokens;
  mapping(address token => RewardDetails) public rewardDetails;
  address public incentiveAddress;

  constructor() Ownable(msg.sender) {}

  function refillRewards() external {
    uint _len = tokens.length();
    if (_len == 0) revert FAILED('AuraRewardHelper: No rewards');

    for (uint i; i < _len; ) {
      address _token = tokens.at(i);
      (, address virtualRewardBalance, ) = REWARD_STASH.tokenInfo(_token);

      if (block.timestamp < IBaseRewardPool(virtualRewardBalance).periodFinish())
        revert FAILED('AuraRewardHelper: Already refilled');

      RewardDetails memory _details = rewardDetails[_token];
      IERC20(_token).transferFrom(_details.from, address(this), _details.ratePerWeek);
      IERC20(_token).transfer(address(REWARD_STASH), _details.ratePerWeek);

      unchecked {
        ++i;
      }
    }

    AURA_BOOSTER_LITE.earmarkRewards(PID, address(0));
    _tokenRecover(AURA_BOOSTER_LITE.crv(), incentiveAddress);
  }

  function rewardPoolMetadata(
    address _token
  ) external view returns (uint256 _periodFinish, address _virtualBalanceRewardPool) {
    if (!tokens.contains(_token)) revert FAILED('AuraRewardHelper: !exists');

    (, address virtualBalanceRewardPool, ) = REWARD_STASH.tokenInfo(_token);
    return (IBaseRewardPool(virtualBalanceRewardPool).periodFinish(), virtualBalanceRewardPool);
  }

  function getTokens() public view returns (address[] memory) {
    return tokens.values();
  }

  function tokenCount() public view returns (uint) {
    return tokens.length();
  }

  function setIncentiveAddress(address _newAddr) external onlyOwner {
    incentiveAddress = _newAddr;
  }

  function updateTokenMetadata(address _token, address _from, uint96 _ratePerWeek) external onlyOwner {
    if (!tokens.contains(_token)) revert FAILED('AuraRewardHelper: token !exists');
    rewardDetails[_token] = RewardDetails({ ratePerWeek: _ratePerWeek, from: _from });
  }

  function addToken(address _token, address _from, uint96 _ratePerWeek) external onlyOwner {
    bool added = tokens.add(_token);
    rewardDetails[_token] = RewardDetails({ ratePerWeek: _ratePerWeek, from: _from });

    if (!added) {
      revert FAILED('AuraRewardHelper: token exists');
    }
  }

  function removeToken(address _token) external onlyOwner {
    bool removed = tokens.remove(_token);
    rewardDetails[_token] = RewardDetails({ ratePerWeek: 0, from: address(0) });

    if (!removed) {
      revert FAILED('AuraRewardHelper: token !exists');
    }
  }

  /**
   * @notice Sweep ERC20 tokens to `_to`
   */
  function sweep(address[] memory _tokens, address _to) external onlyOwner {
    uint _len = _tokens.length;

    for (uint i; i < _len; ) {
      _tokenRecover(_tokens[i], _to);

      unchecked {
        ++i;
      }
    }
  }

  function _tokenRecover(address _token, address _to) private {
    IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
  }

  error FAILED(string);
}

