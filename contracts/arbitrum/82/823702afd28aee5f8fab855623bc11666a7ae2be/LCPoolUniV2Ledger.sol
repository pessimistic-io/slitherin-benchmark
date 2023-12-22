// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./IFeeTierStrate.sol";

import "./Ownable.sol";
import "./Address.sol";
import "./StringUtils.sol";

contract LCPoolUniV2Ledger is Ownable {
  address public v2MasterChef;
  address public pool;
  address public feeStrate;
  string public pendingRewardsFunctionName;

  uint256 private constant MULTIPLIER = 1_0000_0000_0000_0000;

  struct RewardTVLRate {
    uint256 reward;
    uint256 prevReward;
    uint256 tvl;
    uint256 rtr;
    uint256 reInvestIndex;
    bool reInvested;
    uint256 updatedAt;
  }

  struct ReinvestInfo {
    uint256 reward;
    uint256 liquidity;
    uint256 updatedAt;
  }

  struct StakeInfo {
    uint256 amount;   // Staked liquidity
    uint256 debtReward;
    uint256 rtrIndex; // RewardTVLRate index
    uint256 updatedAt;
  }

  // account -> poolId -> basketId -> info basketid=0?lcpool
  mapping (address => mapping (uint256 => mapping (uint256 => StakeInfo))) public userInfo;
  // poolId => info
  mapping (uint256 => RewardTVLRate[]) public poolInfoAll;
  // poolId -> reinvest
  mapping (uint256 => ReinvestInfo[]) public reInvestInfo;

  mapping (address => bool) public managers;
  modifier onlyManager() {
    require(managers[msg.sender], "LC pool ledger: !manager");
    _;
  }

  constructor (
    address _v2MasterChef,
    address _feeStrate,
    string memory _pendingRewardsFunctionName
  ) {
    require(_v2MasterChef != address(0), "LC pool ledger: master chef");
    require(_feeStrate != address(0), "LC pool ledger: feeStrate");

    v2MasterChef = _v2MasterChef;
    feeStrate = _feeStrate;
    pendingRewardsFunctionName = _pendingRewardsFunctionName;
    managers[msg.sender] = true;
  }

  function getLastRewardAmount(uint256 poolId) public view returns(uint256) {
    if (poolInfoAll[poolId].length > 0) {
      return poolInfoAll[poolId][poolInfoAll[poolId].length-1].prevReward;
    }
    return 0;
  }

  function getUserLiquidity(address account, uint256 poolId, uint256 basketId) public view returns(uint256) {
    return userInfo[account][poolId][basketId].amount;
  }

  function updateInfo(address acc, uint256 tId, uint256 bId, uint256 liquidity, uint256 reward, uint256 rewardAfter, uint256 exLp, bool increase) public onlyManager {
    uint256[] memory ivar = new uint256[](6);
    ivar[0] = 0;      // prevTvl
    ivar[1] = 0;      // prevTotalReward
    ivar[2] = reward; // blockReward
    ivar[3] = 0;      // exUserLp
    ivar[4] = 0;      // userReward
    ivar[5] = 0;      // rtr
    if (poolInfoAll[tId].length > 0) {
      RewardTVLRate memory prevRTR = poolInfoAll[tId][poolInfoAll[tId].length-1];
      ivar[0] = prevRTR.tvl;
      ivar[1] = prevRTR.reward;
      ivar[2] = (ivar[2] >= prevRTR.prevReward) ? (ivar[2] - prevRTR.prevReward) : 0;
      ivar[5] = prevRTR.rtr;
    }
    ivar[5] += (ivar[0] > 0 ? ivar[2] * MULTIPLIER / ivar[0] : 0);
    
    (ivar[3], ivar[4]) = getSingleReward(acc, tId, bId, reward, false);

    bool reInvested = false;
    if (exLp > 0) {
      ReinvestInfo memory tmp = ReinvestInfo({
        reward: reward,
        liquidity: exLp,
        updatedAt: block.timestamp
      });
      reInvestInfo[tId].push(tmp);
      reInvested = true;
      ivar[3] += ivar[4] * exLp / reward;
      ivar[0] += exLp;
      userInfo[acc][tId][bId].amount += ivar[3];
      ivar[4] = 0;
    }

    RewardTVLRate memory tmpRTR = RewardTVLRate({
      reward: ivar[1] + ivar[2],
      prevReward: rewardAfter,
      tvl: increase ? ivar[0] + liquidity : (ivar[0] >= liquidity ? ivar[0] - liquidity : 0),
      rtr: ivar[5],
      reInvestIndex: reInvestInfo[tId].length,
      reInvested: reInvested,
      updatedAt: block.timestamp
    });
    poolInfoAll[tId].push(tmpRTR);
    
    if (increase) {
      userInfo[acc][tId][bId].amount += liquidity;
      userInfo[acc][tId][bId].debtReward = ivar[4];
    }
    else {
      if (userInfo[acc][tId][bId].amount >= liquidity) {
        userInfo[acc][tId][bId].amount -= liquidity;
      }
      else {
        userInfo[acc][tId][bId].amount = 0;
      }
      userInfo[acc][tId][bId].debtReward = 0;
    }
    userInfo[acc][tId][bId].rtrIndex = poolInfoAll[tId].length - 1;
    userInfo[acc][tId][bId].updatedAt = block.timestamp;
  }

  function getSingleReward(address acc, uint256 tId, uint256 bId, uint256 currentReward, bool cutfee) public view returns(uint256, uint256) {
    uint256[] memory jvar = new uint256[](7);
    jvar[0] = 0;  // extraLp
    jvar[1] = userInfo[acc][tId][bId].debtReward; // reward
    jvar[2] = userInfo[acc][tId][bId].amount;     // stake[j]
    jvar[3] = 0; // reward for one stage

    if (jvar[2] > 0) {
      uint256 t0 = userInfo[acc][tId][bId].rtrIndex;
      uint256 tn = poolInfoAll[tId].length;
      uint256 index = t0;
      while (index < tn) {
        if (poolInfoAll[tId][index].rtr >= poolInfoAll[tId][t0].rtr) {
          jvar[3] = (jvar[2] + jvar[0]) * (poolInfoAll[tId][index].rtr - poolInfoAll[tId][t0].rtr) / MULTIPLIER;
        }
        else {
          jvar[3] = 0;
        }
        if (poolInfoAll[tId][index].reInvested) {
          jvar[0] += jvar[3] * reInvestInfo[tId][poolInfoAll[tId][index].reInvestIndex-1].liquidity / reInvestInfo[tId][poolInfoAll[tId][index].reInvestIndex-1].reward;
          t0 = index;
          jvar[3] = 0;
        }
        index ++;
      }
      jvar[1] += jvar[3];

      if (poolInfoAll[tId][tn-1].tvl > 0 && currentReward >= poolInfoAll[tId][tn-1].prevReward) {
        jvar[1] = jvar[1] + (jvar[2] + jvar[0]) * (currentReward - poolInfoAll[tId][tn-1].prevReward) / poolInfoAll[tId][tn-1].tvl;
      }
    }

    if (cutfee == false) {
      return (jvar[0], jvar[1]);
    }

    (jvar[4], jvar[5]) = IFeeTierStrate(feeStrate).getTotalFee(bId);
    require(jvar[5] > 0, "LC pool ledger: wrong fee configure");
    jvar[6] = jvar[1] * jvar[4] / jvar[5]; // rewardLc

    if (jvar[6] > 0) {
      uint256[] memory feeIndexs = IFeeTierStrate(feeStrate).getAllTier();
      uint256 len = feeIndexs.length;
      uint256 maxFee = IFeeTierStrate(feeStrate).getMaxFee();
      for (uint256 i=0; i<len; i++) {
        (, ,uint256 fee) = IFeeTierStrate(feeStrate).getTier(feeIndexs[i]);
        uint256 feeAmount = jvar[6] * fee / maxFee;
        if (feeAmount > 0 && jvar[1] >= feeAmount) {
          jvar[1] -= feeAmount;
        }
      }
    }

    return (jvar[0], jvar[1]);
  }

  function getReward(address account, uint256[] memory poolId, uint256[] memory basketIds) public view
    returns(uint256[] memory, uint256[] memory)
  {
    uint256 bLen = basketIds.length;
    uint256 len = poolId.length * bLen;
    uint256[] memory extraLp = new uint256[](len);
    uint256[] memory reward = new uint256[](len);
    for (uint256 x = 0; x < poolId.length; x ++) {
      uint256 currentReward = _rewardsAvailable(poolId[x]);
      if (poolInfoAll[poolId[x]].length > 0) {
        currentReward += poolInfoAll[poolId[x]][poolInfoAll[poolId[x]].length-1].prevReward;
      }
      for (uint256 y = 0; y < bLen; y ++) {
        (extraLp[x*bLen + y], reward[x*bLen + y]) = getSingleReward(account, poolId[x], basketIds[y], currentReward, true);
      }
    }
    return (extraLp, reward);
  }

  function _rewardsAvailable(uint256 poolId) internal view returns (uint256) {
    string memory signature = StringUtils.concat(pendingRewardsFunctionName, "(uint256,address)");
    bytes memory result = Address.functionStaticCall(
      v2MasterChef, 
      abi.encodeWithSignature(
        signature,
        poolId,
        pool
      )
    );  
    return abi.decode(result, (uint256));
  }

  function poolInfoLength(uint256 poolId) public view returns(uint256) {
    return poolInfoAll[poolId].length;
  }

  function reInvestInfoLength(uint256 poolId) public view returns(uint256) {
    return reInvestInfo[poolId].length;
  }

  function setManager(address account, bool access) public onlyOwner {
    managers[account] = access;
  }

  function setPool(address _pool) public onlyManager {
    pool = _pool;
    managers[pool] = true;
  }

  function setFeeStrate(address _feeStrate) external onlyManager {
    require(_feeStrate != address(0), "LC pool ledger: Fee Strate");
    feeStrate = _feeStrate;
  }
}

