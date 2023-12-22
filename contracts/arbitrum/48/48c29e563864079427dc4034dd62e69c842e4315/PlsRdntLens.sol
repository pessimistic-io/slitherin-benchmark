// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import "./IERC20.sol";
import { IPlsRdntDepositor } from "./PlsRdntDepositor.sol";
import { IRateProvider } from "./v2_Interfaces.sol";

interface IPriceProvider {
  function getTokenPrice() external view returns (uint256);

  function getTokenPriceUsd() external view returns (uint256);

  function getLpTokenPrice() external view returns (uint256);

  function getLpTokenPriceUsd() external view returns (uint256);

  /**
   * @notice Returns decimals of price.
   */
  function decimals() external view returns (uint256);

  function update() external;

  function baseAssetChainlinkAdapter() external view returns (address);
}

interface IMultiFeeDistribution {
  struct LockedBalance {
    uint256 amount;
    uint256 unlockTime;
    uint256 multiplier;
    uint256 duration;
  }

  struct Balances {
    uint256 total; // sum of earnings and lockings; no use when LP and RDNT is different
    uint256 unlocked; // RDNT token
    uint256 locked; // LP token or RDNT token
    uint256 lockedWithMultiplier; // Multiplied locked amount
    uint256 earned; // RDNT token
  }

  // IFeeDistribution
  struct RewardData {
    address token;
    uint256 amount;
  }

  function addReward(address rewardsToken) external;

  function removeReward(address _rewardToken) external;

  // IMFD
  function exit(bool claimRewards) external;

  function stake(uint256 amount, address onBehalfOf, uint256 typeIndex) external;

  function rdntToken() external view returns (address);

  function getPriceProvider() external view returns (address);

  function lockInfo(address user) external view returns (LockedBalance[] memory);

  function autocompoundEnabled(address user) external view returns (bool);

  function defaultLockIndex(address _user) external view returns (uint256);

  function autoRelockDisabled(address user) external view returns (bool);

  function totalBalance(address user) external view returns (uint256);

  function lockedBalance(address user) external view returns (uint256);

  function lockedBalances(
    address user
  ) external view returns (uint256, uint256, uint256, uint256, LockedBalance[] memory);

  function getBalances(address _user) external view returns (Balances memory);

  function zapVestingToLp(address _address) external returns (uint256);

  function claimableRewards(address account) external view returns (RewardData[] memory rewards);

  function setDefaultRelockTypeIndex(uint256 _index) external;

  function daoTreasury() external view returns (address);

  function stakingToken() external view returns (address);

  function userSlippage(address) external view returns (uint256);

  function claimFromConverter(address) external;

  function vestTokens(address user, uint256 amount, bool withPenalty) external;

  //IMFDPlus
  function getLastClaimTime(address _user) external returns (uint256);

  function claimBounty(address _user, bool _execute) external returns (bool issueBaseBounty);

  function claimCompound(address _user, bool _execute, uint256 _slippage) external returns (uint256 bountyAmt);

  function setAutocompound(bool _newVal) external;

  function setUserSlippage(uint256 slippage) external;

  function toggleAutocompound() external;

  function getAutocompoundEnabled(address _user) external view returns (bool);
}

interface IEligibilityDataProvider {
  function refresh(address user) external returns (bool currentEligibility);

  function updatePrice() external;

  function requiredEthValue(address user) external view returns (uint256 required);

  function isEligibleForRewards(address _user) external view returns (bool isEligible);

  function lastEligibleTime(address user) external view returns (uint256 lastEligibleTimestamp);

  function lockedUsdValue(address user) external view returns (uint256);

  function requiredUsdValue(address user) external view returns (uint256 required);

  function lastEligibleStatus(address user) external view returns (bool);

  function rewardEligibleAmount(address token) external view returns (uint256);

  function setDqTime(address _user, uint256 _time) external;

  function getDqTime(address _user) external view returns (uint256);

  function autoprune() external returns (uint256 processed);

  function requiredDepositRatio() external view returns (uint256);

  function RATIO_DIVISOR() external view returns (uint256);
}

interface IPlsRdntLens {
  function lockedBalance() external view returns (uint);

  function totalDlpBalance() external view returns (uint);

  function getRdntPriceEth() external view returns (uint256);

  function getRdntPriceUsd() external view returns (uint256);

  function getDlpPriceEth() external view returns (uint256);

  function getDlpPriceUsd() external view returns (uint256);

  function getPlsRdntPriceDlp() external view returns (uint256);

  function getPlsRdntPriceEth() external view returns (uint256);

  function getPlsRdntPriceUsd() external view returns (uint256);
}

contract PlsRdntLens is IPlsRdntLens {
  IERC20 public constant DLP = IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

  //radiant contracts
  IMultiFeeDistribution public constant MFD = IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
  IPriceProvider public constant PP = IPriceProvider(0x76663727c39Dd46Fed5414d6801c4E8890df85cF);

  IEligibilityDataProvider public constant EDP = IEligibilityDataProvider(0xd4966DC49a10aa5467D65f4fA4b1449b5d874399);

  // plutus contracts
  address public constant STAKER = 0x2A2CAFbB239af9159AEecC34AC25521DBd8B5197;
  address public constant DEPOSITOR = 0x4C2C41cFfC920CA9dD5F13E88DcF5062ceF37455;
  IPlsRdntDepositor public immutable NEW_DEPOSITOR;
  address public immutable PLSRDNTV2;

  constructor(IPlsRdntDepositor _newDepositor, address _plsRdntV2) {
    NEW_DEPOSITOR = _newDepositor;
    PLSRDNTV2 = _plsRdntV2;
  }

  /**
   * @notice Get plsRDNT max-locked DLP balance
   */
  function lockedBalance() external view returns (uint) {
    return MFD.lockedBalance(STAKER);
  }

  /**
   * @notice Get plsRDNT total DLP balance
   */
  function totalDlpBalance() external view returns (uint) {
    return MFD.lockedBalance(STAKER) + uint256(NEW_DEPOSITOR.dlpThresholdBalance()) + getDepositorV1ThresholdBalance();
  }

  function getDepositorV1ThresholdBalance() public view returns (uint) {
    uint _bal = DLP.balanceOf(DEPOSITOR);
    uint _frozenNum = 55193771844586743898378;

    return _bal > _frozenNum ? _frozenNum : _bal;
  }

  /**
   * @notice Get RDNT price in ETH (1e8 decimals);
   */
  function getRdntPriceEth() external view returns (uint256) {
    return PP.getTokenPrice();
  }

  /**
   * @notice Get RDNT price in USDC (1e8 decimals);
   */
  function getRdntPriceUsd() external view returns (uint256) {
    return PP.getTokenPriceUsd();
  }

  /**
   * @notice Get DLP price in ETH (1e8 decimals);
   */
  function getDlpPriceEth() public view returns (uint256) {
    return PP.getLpTokenPrice();
  }

  /**
   * @notice Get DLP price in USD (1e8 decimals);
   */
  function getDlpPriceUsd() public view returns (uint256) {
    return PP.getLpTokenPriceUsd();
  }

  /**
   * @notice Get plsRDNT V2 price in DLP (1e8 decimals);
   */
  function getPlsRdntPriceDlp() public view returns (uint256) {
    return IRateProvider(PLSRDNTV2).getRate() / 1e10;
  }

  /**
   * @notice Get plsRDNT V2 price in ETH (1e8 decimals);
   */
  function getPlsRdntPriceEth() external view returns (uint256) {
    return (getPlsRdntPriceDlp() * getDlpPriceEth()) / 1e8;
  }

  /**
   * @notice Get plsRDNT V2 price in USD (1e8 decimals);
   */
  function getPlsRdntPriceUsd() external view returns (uint256) {
    return (getPlsRdntPriceDlp() * getDlpPriceUsd()) / 1e8;
  }
}

