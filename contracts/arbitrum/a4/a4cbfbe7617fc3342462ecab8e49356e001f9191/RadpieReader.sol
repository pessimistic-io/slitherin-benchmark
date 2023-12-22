// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, ERC20 } from "./ERC20.sol";

import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";

import { IMasterRadpieReader } from "./IMasterRadpieReader.sol";
import { IRadpieStakingReader } from "./IRadpieStakingReader.sol";
import { IRDNTRewardManagerReader } from "./IRDNTRewardManagerReader.sol";
import { IRDNTVestManagerReader } from "./IRDNTVestManagerReader.sol";
import { IBaseRewardPoolV3 } from "./IBaseRewardPoolV3.sol";
import { ILendingPool } from "./ILendingPool.sol";
import { IChefIncentivesController } from "./IChefIncentivesController.sol";
import { IMultiFeeDistribution } from "./IMultiFeeDistribution.sol";
import { IPriceProvider } from "./IPriceProvider.sol";
import { IRadpieReceiptToken } from "./IRadpieReceiptToken.sol";
import { IRewardDistributor } from "./IRewardDistributor.sol";

import { IIncentivizedERC20 } from "./IIncentivizedERC20.sol";
import { ReaderDatatype } from "./ReaderDatatype.sol";
import { DataTypes } from "./DataTypes.sol";
import { ReserveConfiguration } from "./ReserveConfiguration.sol";
import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";

import "./console.sol";

/// @title RadpieRader
/// @author Magpie Team

contract RadpieReader is Initializable, OwnableUpgradeable, ReaderDatatype {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address public radpieOFT;
    address public vlRDP;
    address public mDLP;
    address public RDNT;
    address public WETH;
    address public RDNT_LP;
    IMasterRadpieReader public masterRadpie;
    IRadpieStakingReader public radpieStaking;
    IRewardDistributor public rewardDistributor;
    IRDNTRewardManagerReader public rdntRewardManager;
    IRDNTVestManagerReader public rdntVestManager;
    IMultiFeeDistribution public radiantMFD;
    ILendingPool public lendingPool;
    IChefIncentivesController public chefIncentives;

    AggregatorV3Interface public RDNTOracle;
    uint256 constant DENOMINATOR = 10000;
    uint256[] public RDNTrevShare; // 0 LPers // 1 mDLP // 2 vlRDP

    /* ============ Events ============ */

    /* ============ Errors ============ */

    /* ============ Constructor ============ */

    function __RadpieReader_init() public initializer {
        __Ownable_init();
    }

    /* ============ External Getters ============ */

    function getRadpieInfo(address account) external view returns (RadpieInfo memory) {
        RadpieInfo memory info;
        uint256 poolCount = masterRadpie.poolLength();
        RadpiePool[] memory pools = new RadpiePool[](poolCount);

        info.systemRDNTInfo = getRadpieRDNTInfo(account);
        for (uint256 i = 0; i < poolCount; ++i) {
            pools[i] = getRadpiePoolInfo(i, account, info);
        }

        info.pools = pools;
        info.masterRadpie = address(masterRadpie);
        info.radpieStaking = address(radpieStaking);
        info.radpieOFT = radpieOFT;
        info.rdntRewardManager = address(rdntRewardManager);
        info.rdntVestManager = address(rdntVestManager);
        info.vlRDP = vlRDP;
        info.mDLP = mDLP;
        info.RDNT = RDNT;
        info.WETH = WETH;
        info.RDNT_LP = RDNT_LP;
        info.systemHealthFactor = radpieStaking.systemHealthFactor();
        info.minHealthFactor = radpieStaking.minHealthFactor();

        _updateBasedOnRevShare(info);

        return info;
    }

    function getRadpiePoolInfo(
        uint256 poolId,
        address account,
        RadpieInfo memory systemInfo
    ) public view returns (RadpiePool memory) {
        RadpiePool memory radpiePool;
        radpiePool.poolId = poolId;

        address registeredToken = masterRadpie.registeredToken(poolId);

        IMasterRadpieReader.RadpiePoolInfo memory radpiePoolInfo = masterRadpie.tokenToPoolInfo(
            registeredToken
        );

        (
            radpiePool.asset,
            radpiePool.rToken,
            radpiePool.vdToken,
            radpiePool.rewarder,
            ,
            radpiePool.maxCap,
            ,
            ,
            radpiePool.isActive
        ) = radpieStaking.pools(registeredToken);
        radpiePool.helper = radpieStaking.assetLoopHelper();

        radpiePool.stakingToken = radpiePoolInfo.stakingToken;
        radpiePool.receiptToken = radpiePoolInfo.receiptToken;
        (, , radpiePool.sizeOfPool, ) = masterRadpie.getPoolInfo(radpiePool.stakingToken);
        radpiePool.stakedTokenInfo = getERC20TokenInfo(radpiePool.stakingToken);

        uint256 price;
        uint256 assetPerShare = 10 ** 18;

        if (radpiePool.stakingToken == vlRDP) {
            radpiePool.poolType = "vlRDP_POOL";
            radpiePool.tvl =
                (radpiePool.sizeOfPool * price) /
                (10 ** radpiePool.stakedTokenInfo.decimals);
            radpiePool.leveragedTVL = radpiePool.tvl;
            radpiePool.asset = radpiePoolInfo.stakingToken;
            radpiePool.radpieLendingInfo = getRadpieLendingInfo(radpiePool, 0, 0, RDNTrevShare[2]);
        } else if (radpiePool.stakingToken == mDLP) {
            radpiePool.poolType = "mDLP_POOL";
            price = this.getDlpPrice();
            radpiePool.assetPrice = price;
            console.log("radpiePool.sizeOfPool: ", radpiePool.sizeOfPool);
            console.log("radpiePool.assetPrice: ", radpiePool.assetPrice);
            radpiePool.tvl =
                (radpiePool.sizeOfPool * price) /
                (10 ** radpiePool.stakedTokenInfo.decimals);
            console.log("radpiePool.tvl: ", radpiePool.tvl);
            console.log("assetPerShare: ", assetPerShare);
            console.log("price: ", price);
            radpiePool.leveragedTVL = radpiePool.tvl;
            radpiePool.asset = radpiePoolInfo.stakingToken;
            radpiePool.radpieLendingInfo = getRadpieLendingInfo(radpiePool, 0, 0, RDNTrevShare[1]);
        } else {
            // default is Radiant pools
            radpiePool.poolType = "RADIANT_POOL";
            price = IIncentivizedERC20(radpiePool.rToken).getAssetPrice();
            radpiePool.assetPrice = price;
            uint256 rTokenBal = IERC20(radpiePool.rToken).balanceOf(address(radpieStaking));
            uint256 debtBal = IERC20(radpiePool.vdToken).balanceOf(address(radpieStaking));
            assetPerShare = IRadpieReceiptToken(radpiePoolInfo.receiptToken).assetPerShare();
            radpiePool.tvl =
                (radpiePool.sizeOfPool * price * assetPerShare) /
                (10 ** (radpiePool.stakedTokenInfo.decimals + 18));
            radpiePool.debt = (debtBal * price) / (10 ** radpiePool.stakedTokenInfo.decimals);

            radpiePool.leveragedTVL =
                (rTokenBal * price * assetPerShare) /
                (10 ** (radpiePool.stakedTokenInfo.decimals + 18));
            radpiePool.radpieLendingInfo = getRadpieLendingInfo(
                radpiePool,
                rTokenBal,
                debtBal,
                RDNTrevShare[0]
            );
            systemInfo.systemRDNTInfo.totalRDNTpersec += radpiePool.radpieLendingInfo.RDNTpersec;
        }

        uint256 totalReceiptToken = IERC20(radpiePool.receiptToken).totalSupply();
        if (radpiePool.maxCap > totalReceiptToken)
            radpiePool.quotaLeft = ((radpiePool.maxCap - totalReceiptToken)) * assetPerShare / (10 ** 18);

        if (account != address(0)) {
            radpiePool.accountInfo = getRadpieAccountInfo(
                radpiePool,
                account,
                price,
                assetPerShare
            );
            radpiePool.rewardInfo = getRadpieRewardInfo(
                radpiePool.stakingToken,
                radpiePool.receiptToken,
                account
            );
            radpiePool.legacyRewardInfo = getRadpieLegacyRewardInfo(
                radpiePool.stakingToken,
                account
            );
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

    function getRadpieAccountInfo(
        RadpiePool memory pool,
        address account,
        uint256 assetPrice,
        uint256 assetPerShare
    ) public view returns (RadpieAccountInfo memory) {
        RadpieAccountInfo memory accountInfo;

        accountInfo.balance = ERC20(pool.stakingToken).balanceOf(account);
        (accountInfo.stakedAmount, accountInfo.availableAmount) = masterRadpie.stakingInfo(
            pool.stakingToken,
            account
        );

        if (pool.stakingToken == mDLP) {
            accountInfo.stakingAllowance = ERC20(pool.stakingToken).allowance(
                account,
                address(masterRadpie)
            );
            accountInfo.mDLPAllowance = ERC20(RDNT_LP).allowance(account, mDLP);
            accountInfo.rdntDlpBalance = ERC20(RDNT_LP).balanceOf(account);
            accountInfo.rdntBalance = ERC20(RDNT).balanceOf(account);
        } else if (pool.stakingToken == vlRDP) {
            accountInfo.stakingAllowance = ERC20(pool.stakingToken).allowance(
                account,
                address(vlRDP)
            );
        } else {
            accountInfo.stakingAllowance = ERC20(pool.stakingToken).allowance(
                account,
                address(pool.helper)
            );
        }

        accountInfo.tvl =
            (assetPrice * accountInfo.stakedAmount * assetPerShare) /
            (10 ** (pool.stakedTokenInfo.decimals + 18));

        return accountInfo;
    }

    function getRadpieRewardInfo(
        address stakingToken,
        address receipt,
        address account
    ) public view returns (RadpieRewardInfo memory) {
        RadpieRewardInfo memory rewardInfo;
        (
            rewardInfo.pendingRDP,
            rewardInfo.bonusTokenAddresses,
            rewardInfo.bonusTokenSymbols,
            rewardInfo.pendingBonusRewards
        ) = masterRadpie.allPendingTokens(stakingToken, account);
        rewardInfo.entitledRDNT = rdntRewardManager.entitledRDNTByReceipt(account, receipt);
        return rewardInfo;
    }

    function getRadpieLendingInfo(
        RadpiePool memory pool,
        uint256 rTokenBal,
        uint256 vdTokenBal,
        uint256 _RDNTrevShare
    ) public view returns (RadpieLendingInfo memory) {
        RadpieLendingInfo memory lendingInfo;

        if (rTokenBal == 0 && vdTokenBal == 0) return lendingInfo;

        DataTypes.ReserveData memory baseData = lendingPool.getReserveData(pool.asset);

        lendingInfo.depositRate = (DENOMINATOR * baseData.currentLiquidityRate) / (10 ** 27);
        lendingInfo.borrowRate = (DENOMINATOR * baseData.currentVariableBorrowRate) / (10 ** 27);

        uint256 decimal = IERC20Metadata(pool.asset).decimals();
        lendingInfo.depositAPR =
            (rTokenBal * lendingInfo.depositRate * pool.assetPrice) /
            (pool.tvl * 10 ** decimal);
        lendingInfo.borrowAPR =
            (vdTokenBal * lendingInfo.borrowRate * pool.assetPrice) /
            (pool.tvl * 10 ** decimal);

        (, uint256 reserveLiquidationThreshold, , , ) = baseData.configuration.getParamsMemory();

        if (vdTokenBal != 0)
            lendingInfo.healthFactor = (reserveLiquidationThreshold * rTokenBal) / vdTokenBal;

        (lendingInfo.RDNTpersec, lendingInfo.RDNTAPR) = this.getRDNTAPR(pool);
        lendingInfo.RDNTAPR = (_RDNTrevShare * lendingInfo.RDNTAPR) / DENOMINATOR;

        return lendingInfo;
    }

    function getRadpieRDNTInfo(address account) public view returns (RadpieRDNTInfo memory) {
        RadpieRDNTInfo memory radpieRDNTInfo;
        (
            ,
            radpieRDNTInfo.lockedDLPUSD,
            radpieRDNTInfo.totalCollateralUSD,
            radpieRDNTInfo.requiredDLPUSD,

        ) = rewardDistributor.rdntRewardEligibility();
        radpieRDNTInfo.lastHarvestTime = radpieStaking.lastSeenClaimableTime();
        radpieRDNTInfo.nextStartVestTime = rdntRewardManager.nextVestingTime();
        radpieRDNTInfo.totalEarnedRDNT = radpieStaking.totalEarnedRDNT();

        address[] memory tokens = new address[](0);
        (radpieRDNTInfo.systemVestable, , , ) = rewardDistributor.claimableAndPendingRDNT(tokens);

        (
            radpieRDNTInfo.systemVesting,
            radpieRDNTInfo.systemVested,
            radpieRDNTInfo.vestingInfos
        ) = radiantMFD.earnedBalances(address(radpieStaking));

        if (account != address(0)) {
            (
                radpieRDNTInfo.userVestingSchedules,
                ,
                radpieRDNTInfo.userVestedRDNT,
                radpieRDNTInfo.userVestingRDNT
            ) = rdntVestManager.getAllVestingInfo(account);
        }

        return radpieRDNTInfo;
    }

    function getRadpieLegacyRewardInfo(
        address stakingToken,
        address account
    ) public view returns (RadpieLegacyRewardInfo memory) {
        RadpieLegacyRewardInfo memory rewardInfo;
        address rewarderAddress = masterRadpie.legacyRewarders(stakingToken);
        if (rewarderAddress != address(0)) {
            IBaseRewardPoolV3 rewarder = IBaseRewardPoolV3(rewarderAddress);
            (rewardInfo.pendingBonusRewards) = rewarder.allEarned(account);
        }
        return rewardInfo;
    }

    function getRDNTAPR(RadpiePool memory pool) external view returns (uint256, uint256) {
        uint256 RDNTPrice = this.getRDNTPrice();
        uint256 rdntPerSec = _rdntEmission(pool);

        return (rdntPerSec, _anualize(rdntPerSec, RDNTPrice, 18, pool.tvl));
    }

    function getRDNTPrice() external view returns (uint256) {
        return uint256(RDNTOracle.latestAnswer());
    }

    function getDlpPrice() external view returns (uint256) {
        address priceProvider = IMultiFeeDistribution(radiantMFD).getPriceProvider();
        return IPriceProvider(priceProvider).getLpTokenPriceUsd();
    }

    /* ============ Admin functions ============ */

    function init(
        address _mDLP,
        address _RDNT,
        address _WETH,
        address _RDNT_LP,
        address _masterRadpie,
        address _radpieStaking
    ) external onlyOwner {
        mDLP = _mDLP;
        RDNT = _RDNT;
        WETH = _WETH;
        RDNT_LP = _RDNT_LP;
        masterRadpie = IMasterRadpieReader(_masterRadpie);
        radpieStaking = IRadpieStakingReader(_radpieStaking);
    }

    function config(
        address _rdntRewardManager,
        address _rewardDistributor,
        address _radiantMFD,
        address _lendingPool,
        address _RDNTOracle,
        address _chefIncentives
    ) external onlyOwner {
        rdntRewardManager = IRDNTRewardManagerReader(_rdntRewardManager);
        rewardDistributor  =IRewardDistributor(_rewardDistributor);
        radiantMFD = IMultiFeeDistribution(_radiantMFD);
        lendingPool = ILendingPool(_lendingPool);
        rdntVestManager = IRDNTVestManagerReader(radpieStaking.rdntVestManager());
        RDNTOracle = AggregatorV3Interface(_RDNTOracle);
        chefIncentives = IChefIncentivesController(_chefIncentives);
    }

    function addRDNTrevShare(uint256 value) external onlyOwner {
        RDNTrevShare.push(value);
    }

    function RDNTrevShareLength() external view returns (uint256) {
        return RDNTrevShare.length;
    }

    function updateRDNTrevShare(uint256 _index, uint256 _value) external onlyOwner {
        RDNTrevShare[_index] = _value;
    }

    /* ============ Internal functions ============ */

    function _updateBasedOnRevShare(RadpieInfo memory info) internal view {
        uint256 rdntPerSec = info.systemRDNTInfo.totalRDNTpersec;
        uint256 rdntPerSecToMDlp = (rdntPerSec * RDNTrevShare[1]) / DENOMINATOR;
        uint256 RDNTPrice = this.getRDNTPrice();

        // mDLP
        info.pools[0].radpieLendingInfo.RDNTAPR = _anualize(
            rdntPerSecToMDlp,
            RDNTPrice,
            18,
            info.pools[0].tvl
        );
    }

    function _rdntEmission(RadpiePool memory pool) internal view returns (uint256) {
        uint256 rdntRate = chefIncentives.rewardsPerSecond();
        uint256 totalAllocPoint = chefIncentives.totalAllocPoint();

        uint256 rTokenBal = IERC20(pool.rToken).balanceOf(address(radpieStaking));
        uint256 vdTokenBal = IERC20(pool.vdToken).balanceOf(address(radpieStaking));

        (uint256 rTotalSup, uint256 rAllocpoint, , , ) = chefIncentives.poolInfo(pool.rToken);
        (uint256 vdTotalSup, uint256 vdAllocpoint, , , ) = chefIncentives.poolInfo(pool.vdToken);

        uint256 emitForRToken = (rAllocpoint * rdntRate * rTokenBal) /
            (totalAllocPoint * rTotalSup);
        uint256 emitForVdToken = (vdAllocpoint * rdntRate * vdTokenBal) /
            (totalAllocPoint * vdTotalSup);

        return emitForRToken + emitForVdToken;
    }

    function _anualize(
        uint256 _rewardPerSec,
        uint256 _rewardPrice,
        uint256 rewardDecimal,
        uint256 _assetTVL
    ) internal pure returns (uint256) {
        return
            (DENOMINATOR * _rewardPerSec * 86400 * 365 * _rewardPrice) /
            (_assetTVL * 10 ** rewardDecimal);
    }
}

