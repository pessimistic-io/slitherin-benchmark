// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20, ERC20} from "./ERC20.sol";

import {SafeERC20} from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";

import {IMasterRadpieReader} from "./IMasterRadpieReader.sol";
import {IRadpieStakingReader} from "./IRadpieStakingReader.sol";


/// @title RadpieRader
/// @author Magpie Team

contract RadpieReader is Initializable, OwnableUpgradeable {

    struct RadpiePool {
        uint256 poolId;
        address stakingToken; // Address of staking token contract to be staked.
        address receiptToken; // Address of receipt token contract represent a staking position
        uint256 allocPoint; // How many allocation points assigned to this pool. Penpies to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that Penpies distribution occurs.
        uint256 accPenpiePerShare; // Accumulated Penpies per share, times 1e12. See below.
        uint256 totalStaked;
        uint256 emission;
        uint256 allocpoint;
        uint256 sizeOfPool;
        uint256 totalPoint;
        address rewarder;
        bool    isActive;
        bool    isRadiantMarket;
        string  poolType;
        ERC20TokenInfo stakedTokenInfo;
        RadpieAccountInfo  accountInfo;
        RadpieRewardInfo rewardInfo;
    }

    struct RadpieInfo {
        address masterRadpie;
        address radpieStaking;
        address vlRDP;
        address radpieOFT;
        address RDNT;
        address WETH;
        address RDNT_LP;  
        address mDLP;
        RadpiePool[] pools;
    }

    struct ERC20TokenInfo {
        address tokenAddress;
        string symbol;
        uint256 decimals;
    }

    struct RadpieAccountInfo {
        uint256 balance;
        uint256 stakedAmount;
        uint256 stakingAllowance;
        uint256 availableAmount;
        uint256 mDLPAllowance;
        uint256 lockRDPAllowance;
        uint256 rdntBalance;
        uint256 rdpBalance;
    }

    struct RadpieRewardInfo {
        uint256 pendingRDP;
        address[]  bonusTokenAddresses;
        string[]  bonusTokenSymbols;
        uint256[]  pendingBonusRewards;
    }    

    address public radpieOFT;
    address public vlRDP;
    address public mDLP;
    address public RDNT;
    address public WETH;
    address public RDNT_LP;
    IMasterRadpieReader public masterRadpie;
    IRadpieStakingReader public radpieStaking;    


    /* ============ Events ============ */

    /* ============ Errors ============ */

    /* ============ Constructor ============ */

    function __RadpieReader_init() public initializer {
        __Ownable_init();
    }

    /* ============ External Getters ============ */

    function getRadpieInfo(address account)  external view returns (RadpieInfo memory) {
        RadpieInfo memory info;
        uint256 poolCount = masterRadpie.poolLength();
        RadpiePool[] memory pools = new RadpiePool[](poolCount);

        for (uint256 i = 0; i < poolCount; ++i) {
           pools[i] = getRadpiePoolInfo(i, account);
        }

        info.pools = pools;
        info.masterRadpie = address(masterRadpie);
        info.radpieStaking = address(radpieStaking);
        info.radpieOFT = radpieOFT;
        info.vlRDP = vlRDP;
        info.mDLP = mDLP;
        info.RDNT = RDNT;
        info.WETH = WETH;
        info.RDNT_LP = RDNT_LP;
        return info;
    }

    function getRadpiePoolInfo(uint256 poolId, address account) public view returns (RadpiePool memory) {
        RadpiePool memory radpiePool;
        radpiePool.poolId = poolId;
        address registeredToken = masterRadpie.registeredToken(poolId);

        IMasterRadpieReader.RadpiePoolInfo memory radpiePoolInfo = masterRadpie.tokenToPoolInfo(registeredToken);

        radpiePool.stakingToken = radpiePoolInfo.stakingToken;
        radpiePool.allocPoint = radpiePoolInfo.allocPoint;
        radpiePool.lastRewardTimestamp = radpiePoolInfo.lastRewardTimestamp;
        radpiePool.accPenpiePerShare = radpiePoolInfo.accPenpiePerShare;
        radpiePool.totalStaked = radpiePoolInfo.totalStaked;
        radpiePool.rewarder = radpiePoolInfo.rewarder;
        radpiePool.isActive = radpiePoolInfo.isActive;
        radpiePool.receiptToken = radpiePoolInfo.receiptToken;
        (radpiePool.emission, radpiePool.allocpoint, radpiePool.sizeOfPool, radpiePool.totalPoint) = masterRadpie.getPoolInfo(radpiePool.stakingToken);
        if (radpiePool.stakingToken == vlRDP) {
            radpiePool.poolType = "vlRDP_POOL";
            radpiePool.stakedTokenInfo = getERC20TokenInfo(radpiePool.stakingToken);
            // radpiePool.vlPenpieLockInfo = getVlPenpieLockInfo(account);
        }
        else if (radpiePool.stakingToken == mDLP) {
            radpiePool.poolType = "mDLP_POOL";
            radpiePool.stakedTokenInfo = getERC20TokenInfo(radpiePool.stakingToken);
        }

        if (account != address(0)) {
            radpiePool.accountInfo = getRadpieAccountInfo(radpiePool, account);
            radpiePool.rewardInfo = getRadpieRewardInfo(radpiePool.stakingToken, account);
        }
        return radpiePool;
    }

    function getERC20TokenInfo(address token) public view returns (ERC20TokenInfo memory) {
        ERC20TokenInfo memory tokenInfo;
        tokenInfo.tokenAddress = token;
        if (token == address(1)) {
            tokenInfo.symbol = "ETH";
            tokenInfo.decimals = 18;
            return tokenInfo;
        }
        ERC20 tokenContract = ERC20(token);
        tokenInfo.symbol = tokenContract.symbol();
        tokenInfo.decimals = tokenContract.decimals();
        return tokenInfo;
    }

    function getRadpieAccountInfo(RadpiePool memory pool, address account) public view returns (RadpieAccountInfo memory) {
        RadpieAccountInfo memory accountInfo;
        if (pool.isRadiantMarket) {
            // accountInfo.balance = ERC20(pool.pendleMarket.marketAddress).balanceOf(account);
            // accountInfo.stakingAllowance = ERC20(pool.pendleMarket.marketAddress).allowance(account, address(pendleStaking));
            // accountInfo.stakedAmount = ERC20(pool.pendleStakingPoolInfo.receiptToken).balanceOf(account);
        } else {
            accountInfo.balance = ERC20(pool.stakingToken).balanceOf(account);
            accountInfo.stakingAllowance = ERC20(pool.stakingToken).allowance(account, address(masterRadpie));
            (accountInfo.stakedAmount, accountInfo.availableAmount) = masterRadpie.stakingInfo(pool.stakingToken, account);
        }

        if (pool.stakingToken == mDLP) {
            accountInfo.mDLPAllowance = ERC20(RDNT_LP).allowance(account, mDLP);
            accountInfo.rdntBalance = ERC20(RDNT).balanceOf(account);
        }
        // if  (pool.stakingToken == vlRDP) {
        //     accountInfo.lockPenpieAllowance = ERC20(radpieOFT).allowance(account, vlRDP);
        //     accountInfo.penpieBalance = ERC20(radpieOFT).balanceOf(account);
        // }
        
        return accountInfo;
    }

    function getRadpieRewardInfo(address stakingToken, address account) public view returns (RadpieRewardInfo memory) {
        RadpieRewardInfo memory rewardInfo;
        (rewardInfo.pendingRDP, rewardInfo.bonusTokenAddresses, rewardInfo.bonusTokenSymbols, rewardInfo.pendingBonusRewards) = masterRadpie.allPendingTokens(stakingToken, account);
        return rewardInfo;
    }    

    /* ============ Admin functions ============ */

    function init(address _mDLP, address _RDNT, address _WETH, address _RDNT_LP, address _masterRadpie, address _radpieStaking) external onlyOwner {
        mDLP = _mDLP;
        RDNT = _RDNT;
        WETH = _WETH;
        RDNT_LP = _RDNT_LP;
        masterRadpie = IMasterRadpieReader(_masterRadpie);
        radpieStaking = IRadpieStakingReader(_radpieStaking);
    }
}
