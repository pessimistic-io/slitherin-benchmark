// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "./PanaAccessControlled.sol";
import "./IERC20.sol";

abstract contract FrontEndRewarder is PanaAccessControlled {

  /* ========= STATE VARIABLES ========== */

  uint256 public refReward; // % reward for referrer (3 decimals: 100 = 1%)
  uint256 public treasuryReward; // % reward for Treasury (3 decimals: 100 = 1%)
  mapping(address => uint256) public rewards; // front end operator rewards
  mapping(address => bool) public whitelisted; // whitelisted status for operators

  IERC20 internal immutable pana; // reward token
  bool public allowUserRewards; //toggle user reward

  constructor(
    IPanaAuthority _authority, 
    IERC20 _pana
  ) PanaAccessControlled(_authority) {
    pana = _pana;
  }

  /* ========= EXTERNAL FUNCTIONS ========== */

  // pay reward to front end operator
  function getReward() external {
    uint256 reward = rewards[msg.sender];

    rewards[msg.sender] = 0;
    pana.transfer(msg.sender, reward);
  }
  
  /**
  * @notice toggle user having reward, only by governer
  */
  function setUserRewards() external onlyGovernor {        
      allowUserRewards = !allowUserRewards;
  }

  /* ========= INTERNAL ========== */

  /** 
   * @notice adds rewards amount for front end operators and treasury based on _payout
   */
  function giveRewards(
    uint256 _payout,
    address _referral
  ) internal returns (uint256 toRef, uint256 toTreasury) {
    // first we calculate rewards paid to front end operator (referrer) and to the treasurer
    toRef = _payout * refReward / 1e4;
    toTreasury = _payout * treasuryReward / 1e4;

    // and store them in our rewards mapping
    if (whitelisted[_referral]) {
      if(allowUserRewards) {
        rewards[msg.sender] += toRef / 2;
        rewards[_referral] += toRef - (toRef/ 2);
      }
      else {
        rewards[_referral] += toRef;
      }
      rewards[authority.vault()] += toTreasury;
    } else { 
      // the Treasury receives both rewards if referrer is not whitelisted
      rewards[authority.vault()] += toTreasury + toRef;
    }
  }

  /**
   * @notice Send rewards to treasury which was minted as per giveRewards logic
   */
  function sendRewardsToTreasury(uint256 _toTreasury) internal {
    uint256 reward = rewards[authority.vault()];

    if (reward > 0 && reward >= _toTreasury) {
      rewards[authority.vault()] -= _toTreasury;
      pana.transfer(authority.vault(), _toTreasury);
    }
  }

  /**
   * @notice set rewards for front end operators and DAO
   */
  function setRewards(uint256 _toFrontEnd, uint256 _toTreasury) external onlyGovernor {
    refReward = _toFrontEnd;
    treasuryReward = _toTreasury;
  }

  /**
   * @notice add or remove addresses from the reward whitelist
   */
  function whitelist(address _operator) external onlyPolicy {
    whitelisted[_operator] = !whitelisted[_operator];
  }

  /**
   * @notice Manually fetch remaining rewards for Treasury
   */
  function getTreasuryRewards() external onlyGovernor {
    uint256 reward = rewards[authority.vault()];

    if (reward > 0) {
      rewards[authority.vault()] = 0;
      pana.transfer(authority.vault(), reward);
    }
  }
}
