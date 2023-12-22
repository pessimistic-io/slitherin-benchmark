// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";

import "./IGToken.sol";
import "./ICore.sol";
import "./IDashboard.sol";
import "./ILocker.sol";
import "./IGRVDistributor.sol";
import "./IBEP20.sol";
import "./IEcoScore.sol";
import "./IWhiteholePair.sol";
import "./IRebateDistributor.sol";
import "./ILendPoolLoan.sol";

contract Dashboard is IDashboard, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    ICore public core;
    ILocker public locker;
    IGRVDistributor public grvDistributor;
    IEcoScore public ecoScore;
    IWhiteholePair public pairContract;
    IRebateDistributor public rebateDistributor;
    ILendPoolLoan public lendPoolLoan;

    address public GRV;
    address public marketingTreasury;
    address public reserveTreasury;
    address public devTeamTreasury;
    address public taxTreasury;
    address public grvPresale;
    address public rankerRewardDistributor;
    address public swapFeeTreasury;
    address public lpVault;

    bool public isGenesis;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _grvTokenAddress,
        address _core,
        address _locker,
        address _grvDistributor,
        address _ecoScore,
        address _pairContract,
        address _rebateDistributor,
        address _reserveTreasury,
        address _swapFeeTreasury,
        address _devTeamTreasury,
        address _marketingTreasury,
        address _taxTreasury
    ) external initializer {
        __Ownable_init();

        GRV = _grvTokenAddress;
        core = ICore(_core);
        locker = ILocker(_locker);
        grvDistributor = IGRVDistributor(_grvDistributor);
        ecoScore = IEcoScore(_ecoScore);
        pairContract = IWhiteholePair(_pairContract);
        rebateDistributor = IRebateDistributor(_rebateDistributor);
        reserveTreasury = _reserveTreasury;
        swapFeeTreasury = _swapFeeTreasury;
        devTeamTreasury = _devTeamTreasury;
        marketingTreasury = _marketingTreasury;
        taxTreasury = _taxTreasury;
        isGenesis = true;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setGrvPresale(address _grvPresale) external onlyOwner {
        require(_grvPresale != address(0), "Dashboard: invalid grvPresale address");
        grvPresale = _grvPresale;
    }

    function setLpVault(address _lpVault) external onlyOwner {
        require(_lpVault != address(0), "Dashboard: invalid lpvault address");
        lpVault = _lpVault;
    }

    function setRankerRewardDistributor(address _rankerRewardDistributor) external onlyOwner {
        require(_rankerRewardDistributor != address(0), "Dashboard: invalid rankerRewardDistributor");
        rankerRewardDistributor = _rankerRewardDistributor;
    }

    function setLendPoolLoan(address _lendPoolLoan) external onlyOwner {
        require(_lendPoolLoan != address(0), "Dashboard: invalid lendPoolLoan address");
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
    }

    function setIsGenesis(bool _isGenesis) external onlyOwner {
        isGenesis = _isGenesis;
    }

    /* ========== VIEWS ========== */

    function totalCirculating() public view returns (uint256) {
        return
            IBEP20(GRV)
            .totalSupply()
            .sub(IBEP20(GRV).balanceOf(marketingTreasury)) // marketing Treasury
            .sub(IBEP20(GRV).balanceOf(devTeamTreasury)) // dev team Treasury
            .sub(IBEP20(GRV).balanceOf(reserveTreasury)) // reserve Treasury
            .sub(locker.totalBalance()) // Locker
            .sub(IBEP20(GRV).balanceOf(address(pairContract))) // GRV-USDC pair contract
            .sub(IBEP20(GRV).balanceOf(address(grvDistributor))) // grv distributor
            .sub(IBEP20(GRV).balanceOf(taxTreasury)) // tax treasury
            .sub(IBEP20(GRV).balanceOf(grvPresale)) // grv presale
            .sub(IBEP20(GRV).balanceOf(rankerRewardDistributor)) // ranker reward distributor
            .sub(IBEP20(GRV).balanceOf(swapFeeTreasury)) // swap fee treasury
            .sub(IBEP20(GRV).balanceOf(lpVault)); // lp vault
    }

    function vaultDashboardInfo()
        public
        view
        returns (
            uint256 totalCirculation,
            uint256 totalLockedGrv,
            uint256 totalVeGrv,
            uint256 averageLockDuration,
            uint256[] memory thisWeekRebatePoolAmounts,
            address[] memory thisWeekRebatePoolMarkets,
            uint256 thisWeekRebatePoolValue
        )
    {
        totalCirculation = totalCirculating();
        totalLockedGrv = locker.totalBalance();
        (totalVeGrv, ) = locker.totalScore();
        averageLockDuration = totalLockedGrv > 0 ? locker.getLockUnitMax().mul(totalVeGrv).div(totalLockedGrv) : 0;
        (uint256[] memory rebates, address[] memory markets, uint256 value, ) = rebateDistributor.thisWeekRebatePool();
        thisWeekRebatePoolAmounts = rebates;
        thisWeekRebatePoolMarkets = markets;
        thisWeekRebatePoolValue = value;
    }

    function ecoScoreInfo(
        address account
    ) public view returns (Constant.EcoZone ecoZone, uint256 claimTax, uint256 ppt, uint256 ecoDR) {
        Constant.EcoScoreInfo memory userEcoInfo = ecoScore.accountEcoScoreInfoOf(account);
        Constant.EcoPolicyInfo memory ecoTaxInfo = ecoScore.ecoPolicyInfoOf(userEcoInfo.ecoZone);
        (uint256 pptTaxRate, ) = ecoScore.getPptTaxRate(userEcoInfo.ecoZone);
        ecoZone = userEcoInfo.ecoZone;
        claimTax = ecoTaxInfo.claimTax;
        ppt = pptTaxRate;
        ecoDR = userEcoInfo.ecoDR;
    }

    function userLockedGrvInfo(
        address account
    ) public view returns (uint256 lockedBalance, uint256 lockDuration, uint256 firstLockTime) {
        lockedBalance = locker.balanceOf(account);
        lockDuration = locker.expiryOf(account);
        firstLockTime = locker.firstLockTimeInfoOf(account);
    }

    function userVeGrvInfo(address account) public view returns (uint256 veGrv, uint256 vp) {
        veGrv = locker.scoreOf(account);
        (uint256 totalScore, ) = locker.totalScore();
        vp = totalScore > 0 ? veGrv.mul(1e18).div(totalScore) : 0;
    }

    function userRebateInfo(address account) public view returns (RebateData memory) {
        RebateData memory rebateData;
        rebateData.weeklyProfit = rebateDistributor.weeklyProfitOf(account);
        (uint256[] memory rebates, address[] memory markets, , uint256 value) = rebateDistributor.accuredRebates(
            account
        );
        rebateData.unClaimedRebateValue = value;
        rebateData.unClaimedMarkets = markets;
        rebateData.unClaimedRebatesAmount = rebates;
        (uint256[] memory claimedRebates, address[] memory claimedMarkets, uint256 claimed) = rebateDistributor
            .totalClaimedRebates(account);
        rebateData.claimedRebateValue = claimed;
        rebateData.claimedMarkets = claimedMarkets;
        rebateData.claimedRebatesAmount = claimedRebates;

        return rebateData;
    }

    function expectedVeGrvInfo(
        address account,
        uint256 amountOfGrv,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    )
        public
        view
        returns (uint256 expectedVeGrv, uint256 expectedVp, uint256 expectedWeeklyProfit, uint256 currentWeeklyProfit)
    {
        expectedVeGrv = locker.preScoreOf(account, amountOfGrv, expiry, option);
        uint256 veGrv = locker.scoreOf(account);
        uint256 incrementVeGrv = expectedVeGrv > veGrv ? expectedVeGrv.sub(veGrv) : 0;
        (uint256 totalScore, ) = locker.totalScore();
        uint256 expectedTotalScore = totalScore.add(incrementVeGrv);

        expectedVp = expectedTotalScore > 0 ? expectedVeGrv.mul(1e18).div(expectedTotalScore) : 0;
        expectedVp = Math.min(expectedVp, 1e18);
        expectedWeeklyProfit = rebateDistributor.weeklyProfitOfVP(expectedVp);
        currentWeeklyProfit = rebateDistributor.weeklyProfitOf(account);
    }

    /// @notice GRV의 현재가 반환
    function getCurrentGRVPrice() external view override returns (uint256) {
        if (isGenesis) {
            return 3e16;
        } else {
            address token0 = pairContract.token0();
            (uint256 reserve0, uint256 reserve1, ) = pairContract.getReserves();
            uint256 price = 0;
            if (token0 == GRV) {
                price = reserve0 > 0 ? reserve1.mul(1e12).mul(1e18).div(reserve0) : 0;
            } else {
                price = reserve1 > 0 ? reserve0.mul(1e12).mul(1e18).div(reserve1) : 0;
            }
            return price;
        }
    }

    function getVaultInfo(address account) external view override returns (VaultData memory) {
        VaultData memory vaultData;
        {
            (
                uint256 totalCirculation,
                uint256 totalLockedGrv,
                uint256 totalVeGrv,
                uint256 averageLockDuration,
                uint256[] memory thisWeekRebatePoolAmounts,
                address[] memory thisWeekRebatePoolMarkets,
                uint256 thisWeekRebatePoolValue
            ) = vaultDashboardInfo();
            vaultData.totalCirculation = totalCirculation;
            vaultData.totalLockedGrv = totalLockedGrv;
            vaultData.totalVeGrv = totalVeGrv;
            vaultData.averageLockDuration = averageLockDuration;
            vaultData.thisWeekRebatePoolAmounts = thisWeekRebatePoolAmounts;
            vaultData.thisWeekRebatePoolMarkets = thisWeekRebatePoolMarkets;
            vaultData.thisWeekRebatePoolValue = thisWeekRebatePoolValue;
        }
        {
            uint256 accruedGrv = grvDistributor.accruedGRV(core.allMarkets(), account);
            uint256 claimedGrv = (ecoScore.accountEcoScoreInfoOf(account)).claimedGrv;
            vaultData.accruedGrv = accruedGrv;
            vaultData.claimedGrv = claimedGrv;
        }
        {
            (Constant.EcoZone ecoZone, uint256 claimTax, uint256 ppt, uint256 ecoDR) = ecoScoreInfo(account);
            vaultData.ecoZone = ecoZone;
            vaultData.claimTax = claimTax;
            vaultData.ppt = ppt;
            vaultData.ecoDR = ecoDR;
        }
        {
            (uint256 lockedBalance, uint256 lockDuration, uint256 firstLockTime) = userLockedGrvInfo(
                account
            );
            vaultData.lockedBalance = lockedBalance;
            vaultData.lockDuration = lockDuration;
            vaultData.firstLockTime = firstLockTime;
        }
        {
            (uint256 veGrv, uint256 vp) = userVeGrvInfo(account);
            RebateData memory rebateData = userRebateInfo(account);
            vaultData.myVeGrv = veGrv;
            vaultData.vp = vp;
            vaultData.rebateData = rebateData;
        }

        return vaultData;
    }

    function getLockUnclaimedGrvModalInfo(address account) external view override returns (CompoundData memory) {
        require(locker.balanceOf(account) > 0, "Dashboard: getLockUnclaimedGrvModalInfo: User has not locked");
        CompoundData memory compoundData;
        uint256 accruedGrv = grvDistributor.accruedGRV(core.allMarkets(), account);
        uint256 expiry = locker.expiryOf(account);
        (uint256 adjustedValue, ) = ecoScore.calculateCompoundTaxes(
            account,
            accruedGrv,
            expiry,
            Constant.EcoScorePreviewOption.LOCK_MORE
        );
        {
            compoundData.accruedGrv = accruedGrv;
            compoundData.lockDuration = expiry;
        }
        {
            compoundData.taxData.prevClaimTaxRate = ecoScore
                .ecoPolicyInfoOf(ecoScore.accountEcoScoreInfoOf(account).ecoZone)
                .claimTax;
            compoundData.taxData.nextClaimTaxRate = ecoScore.getClaimTaxRate(
                account,
                accruedGrv,
                expiry,
                Constant.EcoScorePreviewOption.LOCK_MORE
            );
            compoundData.taxData.discountTaxRate = ecoScore.getDiscountTaxRate(account);
            compoundData.taxData.afterTaxesGrv = adjustedValue;
        }
        {
            Constant.EcoScoreInfo memory userEcoScoreInfo = ecoScore.accountEcoScoreInfoOf(account);
            (Constant.EcoZone ecoZone, uint256 ecoDR, ) = ecoScore.calculatePreUserEcoScoreInfo(
                account,
                adjustedValue,
                expiry,
                Constant.EcoScorePreviewOption.LOCK_MORE
            );
            (uint256 pptTaxRate, ) = ecoScore.getPptTaxRate(userEcoScoreInfo.ecoZone);

            compoundData.ecoScoreData.prevEcoDR = userEcoScoreInfo.ecoDR;
            compoundData.ecoScoreData.prevEcoZone = userEcoScoreInfo.ecoZone;
            compoundData.ecoScoreData.nextEcoDR = ecoDR;
            compoundData.ecoScoreData.nextEcoZone = ecoZone;

            compoundData.taxData.prevPPTRate = pptTaxRate;
            if (userEcoScoreInfo.ecoZone == ecoZone) {
                compoundData.taxData.nextPPTRate = pptTaxRate;
            } else {
                (uint256 nextPptTaxRate, ) = ecoScore.getPptTaxRate(ecoZone);
                compoundData.taxData.nextPPTRate = nextPptTaxRate;
            }
        }
        {
            (
                uint256 expectedVeGrv,
                uint256 expectedVp,
                uint256 expectedWeeklyProfit,
                uint256 currentWeeklyProfit
            ) = expectedVeGrvInfo(account, adjustedValue, expiry, Constant.EcoScorePreviewOption.LOCK_MORE);
            (uint256 veGrv, uint256 vp) = userVeGrvInfo(account);
            compoundData.veGrvData.prevVeGrv = veGrv;
            compoundData.veGrvData.prevVotingPower = vp;
            compoundData.veGrvData.nextVeGrv = expectedVeGrv;
            compoundData.veGrvData.nextVotingPower = expectedVp;
            compoundData.veGrvData.nextWeeklyRebate = expectedWeeklyProfit;
            compoundData.veGrvData.prevWeeklyRebate = currentWeeklyProfit;
        }
        {
            BoostedAprParams memory data;
            data.account = account;
            data.amount = adjustedValue;
            data.expiry = expiry;
            data.option = Constant.EcoScorePreviewOption.LOCK_MORE;
            BoostedAprData memory aprData = getBoostedApr(data);
            compoundData.boostedAprData = aprData;
        }
        return compoundData;
    }

    function getInitialLockUnclaimedGrvModalInfo(
        address account,
        uint256 expiry
    ) external view override returns (CompoundData memory) {
        require(locker.balanceOf(account) == 0, "Dashboard: getInitialLockUnclaimedGrvModalInfo: User already locked");
        CompoundData memory compoundData;
        uint256 accruedGrv = grvDistributor.accruedGRV(core.allMarkets(), account);
        (uint256 adjustedValue, ) = ecoScore.calculateCompoundTaxes(
            account,
            accruedGrv,
            expiry,
            Constant.EcoScorePreviewOption.LOCK
        );
        {
            uint256 truncatedExpiryOfUser = locker.truncateExpiry(expiry);
            compoundData.accruedGrv = accruedGrv;
            compoundData.nextLockDuration = truncatedExpiryOfUser;
        }
        {
            compoundData.taxData.prevClaimTaxRate = ecoScore
                .ecoPolicyInfoOf(ecoScore.accountEcoScoreInfoOf(account).ecoZone)
                .claimTax;
            compoundData.taxData.nextClaimTaxRate = ecoScore.getClaimTaxRate(
                account,
                accruedGrv,
                expiry,
                Constant.EcoScorePreviewOption.LOCK
            );
            compoundData.taxData.discountTaxRate = ecoScore.getDiscountTaxRate(account);
            compoundData.taxData.afterTaxesGrv = adjustedValue;
        }
        {
            Constant.EcoScoreInfo memory userEcoScoreInfo = ecoScore.accountEcoScoreInfoOf(account);
            (Constant.EcoZone ecoZone, uint256 ecoDR, ) = ecoScore.calculatePreUserEcoScoreInfo(
                account,
                adjustedValue,
                expiry,
                Constant.EcoScorePreviewOption.LOCK
            );
            (uint256 pptTaxRate, ) = ecoScore.getPptTaxRate(userEcoScoreInfo.ecoZone);

            compoundData.ecoScoreData.prevEcoDR = userEcoScoreInfo.ecoDR;
            compoundData.ecoScoreData.prevEcoZone = userEcoScoreInfo.ecoZone;
            compoundData.ecoScoreData.nextEcoDR = ecoDR;
            compoundData.ecoScoreData.nextEcoZone = ecoZone;

            compoundData.taxData.prevPPTRate = pptTaxRate;
            if (userEcoScoreInfo.ecoZone == ecoZone) {
                compoundData.taxData.nextPPTRate = pptTaxRate;
            } else {
                (uint256 nextPptTaxRate, ) = ecoScore.getPptTaxRate(ecoZone);
                compoundData.taxData.nextPPTRate = nextPptTaxRate;
            }
        }
        {
            (
                uint256 expectedVeGrv,
                uint256 expectedVp,
                uint256 expectedWeeklyProfit,
                uint256 currentWeeklyProfit
            ) = expectedVeGrvInfo(account, adjustedValue, expiry, Constant.EcoScorePreviewOption.LOCK);
            (uint256 veGrv, uint256 vp) = userVeGrvInfo(account);
            compoundData.veGrvData.prevVeGrv = veGrv;
            compoundData.veGrvData.prevVotingPower = vp;
            compoundData.veGrvData.nextVeGrv = expectedVeGrv;
            compoundData.veGrvData.nextVotingPower = expectedVp;
            compoundData.veGrvData.nextWeeklyRebate = expectedWeeklyProfit;
            compoundData.veGrvData.prevWeeklyRebate = currentWeeklyProfit;
        }
        {
            BoostedAprParams memory data;
            data.account = account;
            data.amount = adjustedValue;
            data.expiry = expiry;
            data.option = Constant.EcoScorePreviewOption.LOCK;
            BoostedAprData memory aprData = getBoostedApr(data);
            compoundData.boostedAprData = aprData;
        }
        return compoundData;
    }

    /// @notice Lock, Lock more, Extend 모달 데이터
    /// @param account user address
    /// @param amount input grv amount
    /// @param expiry input expiry
    /// @param option Lock, Lock More, Extend
    function getLockModalInfo(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (LockData memory) {
        uint256 expiryOfUser = locker.expiryOf(account);
        uint256 truncatedExpiryOfUser = expiry > 0 ? locker.truncateExpiry(expiry) : 0;
        if (expiry == 0 && option == Constant.EcoScorePreviewOption.LOCK_MORE) {
            expiry = expiryOfUser;
            truncatedExpiryOfUser = expiryOfUser;
        }
        if (option == Constant.EcoScorePreviewOption.EXTEND) {
            if (amount == 0) {
                amount = locker.balanceOf(account);
            }
            if (expiry == 0) {
                expiry = expiryOfUser;
                truncatedExpiryOfUser = expiryOfUser;
            }
        }
        LockData memory lockData;
        {
            (Constant.EcoZone ecoZone, uint256 ecoDR, ) = ecoScore.calculatePreUserEcoScoreInfo(
                account,
                amount,
                expiry,
                option
            );
            Constant.EcoScoreInfo memory ecoScoreInfoData = ecoScore.accountEcoScoreInfoOf(account);
            lockData.ecoScoreData.prevEcoDR = ecoScoreInfoData.ecoDR;
            lockData.ecoScoreData.prevEcoZone = ecoScoreInfoData.ecoZone;
            lockData.ecoScoreData.nextEcoDR = ecoDR;
            lockData.ecoScoreData.nextEcoZone = ecoZone;
        }
        {
            (
                uint256 expectedVeGrv,
                uint256 expectedVp,
                uint256 expectedWeeklyProfit,
                uint256 currentWeeklyProfit
            ) = expectedVeGrvInfo(account, amount, expiry, option);
            (uint256 veGrv, uint256 vp) = userVeGrvInfo(account);

            lockData.veGrvData.prevVeGrv = veGrv;
            lockData.veGrvData.prevVotingPower = vp;
            lockData.veGrvData.nextVeGrv = expectedVeGrv;
            lockData.veGrvData.nextVotingPower = expectedVp;
            lockData.veGrvData.nextWeeklyRebate = expectedWeeklyProfit;
            lockData.veGrvData.prevWeeklyRebate = currentWeeklyProfit;
        }
        {
            BoostedAprParams memory data;
            data.account = account;
            data.amount = amount;
            data.expiry = expiry;
            data.option = option;
            BoostedAprData memory aprData = getBoostedApr(data);
            lockData.boostedAprData = aprData;
        }
        {
            lockData.lockDuration = expiryOfUser;
            lockData.nextLockDuration = truncatedExpiryOfUser;
            lockData.lockedGrv = locker.balanceOf(account);
        }
        return lockData;
    }

    function getClaimModalInfo(address account) external view override returns (ClaimData memory) {
        ClaimData memory claimData;
        uint256 accruedGrv = grvDistributor.accruedGRV(core.allMarkets(), account);
        {
            (Constant.EcoZone ecoZone, uint256 ecoDR, ) = ecoScore.calculatePreUserEcoScoreInfo(
                account,
                accruedGrv,
                0,
                Constant.EcoScorePreviewOption.CLAIM
            );
            Constant.EcoScoreInfo memory ecoScoreInfoData = ecoScore.accountEcoScoreInfoOf(account);
            (uint256 pptTaxRate, ) = ecoScore.getPptTaxRate(ecoScoreInfoData.ecoZone);

            claimData.taxData.prevPPTRate = pptTaxRate;
            if (ecoScoreInfoData.ecoZone == ecoZone) {
                claimData.taxData.nextPPTRate = pptTaxRate;
            } else {
                (uint256 nextPptTaxRate, ) = ecoScore.getPptTaxRate(ecoZone);
                claimData.taxData.nextPPTRate = nextPptTaxRate;
            }
            claimData.ecoScoreData.prevEcoDR = ecoScoreInfoData.ecoDR;
            claimData.ecoScoreData.prevEcoZone = ecoScoreInfoData.ecoZone;
            claimData.ecoScoreData.nextEcoDR = ecoDR;
            claimData.ecoScoreData.nextEcoZone = ecoZone;
        }
        {
            (uint256 adjustedValue, ) = ecoScore.calculateClaimTaxes(account, accruedGrv);
            claimData.taxData.prevClaimTaxRate = ecoScore
                .ecoPolicyInfoOf(ecoScore.accountEcoScoreInfoOf(account).ecoZone)
                .claimTax;
            claimData.taxData.nextClaimTaxRate = ecoScore.getClaimTaxRate(
                account,
                accruedGrv,
                0,
                Constant.EcoScorePreviewOption.CLAIM
            );
            claimData.taxData.afterTaxesGrv = adjustedValue;
        }

        claimData.accruedGrv = accruedGrv;

        return claimData;
    }

    function getBoostedApr(BoostedAprParams memory data) public view returns (BoostedAprData memory) {
        address[] memory markets = core.allMarkets();
        BoostedAprData memory aprData;
        aprData.boostedAprDetailList = new BoostedAprDetails[](markets.length);

        for (uint256 i = 0; i < markets.length; i++) {
            aprData.boostedAprDetailList[i] = _calculateBoostedAprInfo(markets[i], data);
        }
        return aprData;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _calculateBoostedAprInfo(
        address market,
        BoostedAprParams memory data
    ) private view returns (BoostedAprDetails memory) {
        BoostedAprDetails memory aprDetailInfo;
        aprDetailInfo.market = market;
        address _account = data.account;
        Constant.DistributionAPY memory apyDistribution = grvDistributor.apyDistributionOf(market, _account);
        {
            aprDetailInfo.currentSupplyApr = apyDistribution.apyAccountSupplyGRV;
            aprDetailInfo.currentBorrowApr = apyDistribution.apyAccountBorrowGRV;
        }
        {
            uint256 accountSupply = IGToken(market).balanceOf(_account);
            uint256 accountBorrow = IGToken(market).borrowBalanceOf(_account).mul(1e18).div(
                IGToken(market).getAccInterestIndex()
            );

            if (IGToken(market).underlying() == address(0)) {
                uint256 nftAccInterestIndex = lendPoolLoan.getAccInterestIndex();
                uint256 nftBorrow = lendPoolLoan.userBorrowBalance(_account).mul(1e18).div(nftAccInterestIndex);
                accountBorrow = accountBorrow.add(nftBorrow);
            }

            (uint256 preBoostedSupply, uint256 preBoostedBorrow) = grvDistributor.getPreEcoBoostedInfo(
                market,
                _account,
                data.amount,
                data.expiry,
                data.option
            );
            uint256 expectedApyAccountSupplyGRV = accountSupply > 0
                ? apyDistribution.apySupplyGRV.mul(preBoostedSupply).div(accountSupply)
                : 0;

            uint256 expectedApyAccountBorrowGRV = accountBorrow > 0
                ? apyDistribution.apyBorrowGRV.mul(preBoostedBorrow).div(accountBorrow)
                : 0;

            aprDetailInfo.expectedSupplyApr = expectedApyAccountSupplyGRV;
            aprDetailInfo.expectedBorrowApr = expectedApyAccountBorrowGRV;
        }
        return aprDetailInfo;
    }
}

