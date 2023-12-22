// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";
import "./SafeMath.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./SafeToken.sol";

import "./IBEP20.sol";
import "./IGRVDistributor.sol";
import "./ILocker.sol";
import "./IGToken.sol";
import "./ICore.sol";
import "./IPriceCalculator.sol";
import "./IEcoScore.sol";
import "./IDashboard.sol";
import "./ILendPoolLoan.sol";

contract GRVDistributor is IGRVDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 private constant LAUNCH_TIMESTAMP = 1681117200;

    /* ========== STATE VARIABLES ========== */

    ICore public core;
    ILocker public locker;
    IPriceCalculator public priceCalculator;
    IEcoScore public ecoScore;
    IDashboard public dashboard;
    ILendPoolLoan public lendPoolLoan;

    mapping(address => Constant.DistributionInfo) public distributions; // Market => DistributionInfo
    mapping(address => mapping(address => Constant.DistributionAccountInfo)) // Market => Account => DistributionAccountInfo
        public accountDistributions; // 토큰별, 유저별 distribution 정보
    mapping(address => uint256) public kickInfo; // user kick count stored

    address public GRV;
    address public taxTreasury;

    /* ========== MODIFIERS ========== */

    /// @notice timestamp에 따른 distribution 정보 갱신
    /// @dev 마지막 time과 비교하여 시간이 지난 경우 해당 시간만큼 쌓인 이자를 계산하여 accPerShareSupply 값을 갱신시켜준다.
    /// @param market gToken address
    modifier updateDistributionOf(address market) {
        Constant.DistributionInfo storage dist = distributions[market];
        if (dist.accruedAt == 0) {
            dist.accruedAt = block.timestamp;
        }

        uint256 timeElapsed = block.timestamp > dist.accruedAt ? block.timestamp.sub(dist.accruedAt) : 0;
        if (timeElapsed > 0) {
            if (dist.totalBoostedSupply > 0) {
                dist.accPerShareSupply = dist.accPerShareSupply.add(
                    dist.supplySpeed.mul(timeElapsed).mul(1e18).div(dist.totalBoostedSupply)
                );
            }
            if (dist.totalBoostedBorrow > 0) {
                dist.accPerShareBorrow = dist.accPerShareBorrow.add(
                    dist.borrowSpeed.mul(timeElapsed).mul(1e18).div(dist.totalBoostedBorrow)
                );
            }
        }
        dist.accruedAt = block.timestamp;
        _;
    }

    /// @dev msg.sender 가 core address 인지 검증
    modifier onlyCore() {
        require(msg.sender == address(core), "GRVDistributor: caller is not Core");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize(
        address _grvTokenAddress,
        address _core,
        address _locker,
        address _priceCalculator
    ) external initializer {
        require(_grvTokenAddress != address(0), "GRVDistributor: grv address can't be zero");
        require(_core != address(0), "GRVDistributor: core address can't be zero");
        require(address(locker) == address(0), "GRVDistributor: locker already set");
        require(address(core) == address(0), "GRVDistributor: core already set");
        require(_locker != address(0), "GRVDistributor: locker address can't be zero");
        require(_priceCalculator != address(0), "GRVDistributor: priceCalculator address can't be zero");

        __Ownable_init();
        __ReentrancyGuard_init();

        GRV = _grvTokenAddress;
        core = ICore(_core);
        locker = ILocker(_locker);
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function approve(address _spender, uint256 amount) external override onlyOwner returns (bool) {
        GRV.safeApprove(_spender, amount);
        return true;
    }

    /// @notice core address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    ///      설정 이후에는 다른 주소로 변경할 수 없음
    /// @param _core core contract address
    function setCore(address _core) public onlyOwner {
        require(_core != address(0), "GRVDistributor: invalid core address");
        require(address(core) == address(0), "GRVDistributor: core already set");
        core = ICore(_core);

        emit SetCore(_core);
    }

    /// @notice priceCalculator address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    /// @param _priceCalculator priceCalculator contract address
    function setPriceCalculator(address _priceCalculator) public onlyOwner {
        require(_priceCalculator != address(0), "GRVDistributor: invalid priceCalculator address");
        priceCalculator = IPriceCalculator(_priceCalculator);

        emit SetPriceCalculator(_priceCalculator);
    }

    /// @notice EcoScore address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    /// @param _ecoScore EcoScore contract address
    function setEcoScore(address _ecoScore) public onlyOwner {
        require(_ecoScore != address(0), "GRVDistributor: invalid ecoScore address");
        ecoScore = IEcoScore(_ecoScore);

        emit SetEcoScore(_ecoScore);
    }

    /// @notice dashboard contract 변경
    /// @dev owner address 에서만 요청 가능
    /// @param _dashboard dashboard contract address
    function setDashboard(address _dashboard) public onlyOwner {
        require(_dashboard != address(0), "GRVDistributor: invalid dashboard address");
        dashboard = IDashboard(_dashboard);

        emit SetDashboard(_dashboard);
    }

    function setTaxTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "GRVDistributor: Tax Treasury can't be zero address");
        taxTreasury = _treasury;
        emit SetTaxTreasury(_treasury);
    }

    /// @notice gToken 의 supplySpeed, borrowSpeed 설정
    /// @dev owner 만 실행 가능
    /// @param gToken gToken address
    /// @param supplySpeed New supply speed
    /// @param borrowSpeed New borrow speed
    function setGRVDistributionSpeed(
        address gToken,
        uint256 supplySpeed,
        uint256 borrowSpeed
    ) external onlyOwner updateDistributionOf(gToken) {
        require(gToken != address(0), "GRVDistributor: setGRVDistributionSpeedL: gToken can't be zero address");
        require(supplySpeed > 0, "GRVDistributor: setGRVDistributionSpeedL: supplySpeed can't be zero");
        require(borrowSpeed > 0, "GRVDistributor: setGRVDistributionSpeedL: borrowSpeed can't be zero");
        Constant.DistributionInfo storage dist = distributions[gToken];
        dist.supplySpeed = supplySpeed;
        dist.borrowSpeed = borrowSpeed;
        emit GRVDistributionSpeedUpdated(gToken, supplySpeed, borrowSpeed);
    }

    function setLendPoolLoan(address _lendPoolLoan) external onlyOwner {
        require(_lendPoolLoan != address(0), "GRVDistributor: lendPoolLoan can't be zero address");
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
        emit SetLendPoolLoan(_lendPoolLoan);
    }

    /* ========== VIEWS ========== */

    function accruedGRV(address[] calldata markets, address account) external view override returns (uint256) {
        uint256 amount = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            amount = amount.add(_accruedGRV(markets[i], account));
        }
        return amount;
    }

    /// @notice 토큰의 distribition 정보 전달
    /// @param market gToken address
    function distributionInfoOf(address market) external view override returns (Constant.DistributionInfo memory) {
        return distributions[market];
    }

    /// @notice 해당 토큰의 유저 distribition 정보 전달
    /// @param market gToken address
    /// @param account user address
    function accountDistributionInfoOf(
        address market,
        address account
    ) external view override returns (Constant.DistributionAccountInfo memory) {
        return accountDistributions[market][account];
    }

    /// @notice 해당 토큰 및 유저의 apy 정보 전달
    /// @param market gToken address
    /// @param account user address
    function apyDistributionOf(
        address market,
        address account
    ) external view override returns (Constant.DistributionAPY memory) {
        (uint256 apySupplyGRV, uint256 apyBorrowGRV) = _calculateMarketDistributionAPY(market);
        (uint256 apyAccountSupplyGRV, uint256 apyAccountBorrowGRV) = _calculateAccountDistributionAPY(market, account);
        return Constant.DistributionAPY(apySupplyGRV, apyBorrowGRV, apyAccountSupplyGRV, apyAccountBorrowGRV);
    }

    /// @notice 특정 유저의 해당 토큰의 boost 비율값 전달
    /// @dev 토큰 담보양, 토큰 대출양(이자인덱스 고려), boostedSupplyRatio= 개인의 부스트 비율에 자신의 담보양을 나눠 계산, boostedBorrowRatio= 개인의 부스트 비율에 자신의 대출양을 나눠 계산
    /// @param market gToken address
    /// @param account user address
    function boostedRatioOf(
        address market,
        address account
    ) external view override returns (uint256 boostedSupplyRatio, uint256 boostedBorrowRatio) {
        uint256 accountSupply = IGToken(market).balanceOf(account);
        uint256 accountBorrow = IGToken(market).borrowBalanceOf(account).mul(1e18).div(
            IGToken(market).getAccInterestIndex()
        );

        if (IGToken(market).underlying() == address(0)) {
            uint256 nftAccInterestIndex = lendPoolLoan.getAccInterestIndex();
            uint256 nftAccountBorrow = lendPoolLoan.userBorrowBalance(account).mul(1e18).div(nftAccInterestIndex);
            accountBorrow = accountBorrow.add(nftAccountBorrow);
        }

        boostedSupplyRatio = accountSupply > 0
            ? accountDistributions[market][account].boostedSupply.mul(1e18).div(accountSupply)
            : 0;
        boostedBorrowRatio = accountBorrow > 0
            ? accountDistributions[market][account].boostedBorrow.mul(1e18).div(accountBorrow)
            : 0;
    }

    function getTaxTreasury() external view override returns (address) {
        return taxTreasury;
    }

    function getPreEcoBoostedInfo(
        address market,
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (uint256 boostedSupply, uint256 boostedBorrow) {
        uint256 expectedUserScore = locker.preScoreOf(account, amount, expiry, option);
        (uint256 totalScore, ) = locker.totalScore();
        uint256 userScore = locker.scoreOf(account);

        uint256 incrementUserScore = expectedUserScore > userScore ? expectedUserScore.sub(userScore) : 0;

        uint256 expectedTotalScore = totalScore.add(incrementUserScore);
        (Constant.EcoZone ecoZone, , ) = ecoScore.calculatePreUserEcoScoreInfo(account, amount, expiry, option);
        boostedSupply = ecoScore.calculatePreEcoBoostedSupply(
            market,
            account,
            expectedUserScore,
            expectedTotalScore,
            ecoZone
        );
        boostedBorrow = ecoScore.calculatePreEcoBoostedBorrow(
            market,
            account,
            expectedUserScore,
            expectedTotalScore,
            ecoZone
        );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Supply 또는 redeem 발생시 해당 유저의 boostedSupply, accruedGRV, accPerShareSupply값을 갱신 -> 시간에 따른 GRV 토큰 보상 업데이트
    /// @param market gToken address
    /// @param user user address
    function notifySupplyUpdated(
        address market,
        address user
    ) external override nonReentrant onlyCore updateDistributionOf(market) {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;

        Constant.DistributionInfo storage dist = distributions[market];
        Constant.DistributionAccountInfo storage userInfo = accountDistributions[market][user];

        if (userInfo.boostedSupply > 0) {
            uint256 accGRVPerShare = dist.accPerShareSupply.sub(userInfo.accPerShareSupply);
            userInfo.accruedGRV = userInfo.accruedGRV.add(accGRVPerShare.mul(userInfo.boostedSupply).div(1e18));
        }
        userInfo.accPerShareSupply = dist.accPerShareSupply;

        uint256 userScore = locker.scoreOf(user);
        (uint256 totalScore, ) = locker.totalScore();

        ecoScore.updateUserEcoScoreInfo(user);
        uint256 boostedSupply = ecoScore.calculateEcoBoostedSupply(market, user, userScore, totalScore);

        dist.totalBoostedSupply = dist.totalBoostedSupply.add(boostedSupply).sub(userInfo.boostedSupply);
        userInfo.boostedSupply = boostedSupply;
    }

    /// @notice Borrow 또는 Repay 발생시 해당 유저의 boostedBorrow, accruedGRV, accPerShareBorrow 갱신 -> 시간에 따른 GRV 토큰 보상 업데이트
    /// @param market gToken address
    /// @param user user address
    function notifyBorrowUpdated(
        address market,
        address user
    ) external override nonReentrant onlyCore updateDistributionOf(market) {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;

        Constant.DistributionInfo storage dist = distributions[market];
        Constant.DistributionAccountInfo storage userInfo = accountDistributions[market][user];

        if (userInfo.boostedBorrow > 0) {
            uint256 accGRVPerShare = dist.accPerShareBorrow.sub(userInfo.accPerShareBorrow);
            userInfo.accruedGRV = userInfo.accruedGRV.add(accGRVPerShare.mul(userInfo.boostedBorrow).div(1e18));
        }
        userInfo.accPerShareBorrow = dist.accPerShareBorrow;

        uint256 userScore = locker.scoreOf(user);
        (uint256 totalScore, ) = locker.totalScore();

        ecoScore.updateUserEcoScoreInfo(user);
        uint256 boostedBorrow = ecoScore.calculateEcoBoostedBorrow(market, user, userScore, totalScore);

        dist.totalBoostedBorrow = dist.totalBoostedBorrow.add(boostedBorrow).sub(userInfo.boostedBorrow);
        userInfo.boostedBorrow = boostedBorrow;
    }

    /// @notice 특정 토큰 전송시 이자 내용 업데이트
    /// @dev 전송자와 수신자의 각각의 남은 보상 이자를 처리한 후 각자의 부스트율 업데이트
    /// @param gToken gToken address
    /// @param sender sender address
    /// @param receiver receiver address
    function notifyTransferred(
        address gToken,
        address sender,
        address receiver
    ) external override nonReentrant onlyCore updateDistributionOf(gToken) {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;

        require(sender != receiver, "GRVDistributor: invalid transfer");
        Constant.DistributionInfo storage dist = distributions[gToken];
        Constant.DistributionAccountInfo storage senderInfo = accountDistributions[gToken][sender];
        Constant.DistributionAccountInfo storage receiverInfo = accountDistributions[gToken][receiver];

        if (senderInfo.boostedSupply > 0) {
            uint256 accGRVPerShare = dist.accPerShareSupply.sub(senderInfo.accPerShareSupply);
            senderInfo.accruedGRV = senderInfo.accruedGRV.add(accGRVPerShare.mul(senderInfo.boostedSupply).div(1e18));
        }
        senderInfo.accPerShareSupply = dist.accPerShareSupply;

        if (receiverInfo.boostedSupply > 0) {
            uint256 accGRVPerShare = dist.accPerShareSupply.sub(receiverInfo.accPerShareSupply);
            receiverInfo.accruedGRV = receiverInfo.accruedGRV.add(
                accGRVPerShare.mul(receiverInfo.boostedSupply).div(1e18)
            );
        }
        receiverInfo.accPerShareSupply = dist.accPerShareSupply;

        uint256 senderScore = locker.scoreOf(sender);
        uint256 receiverScore = locker.scoreOf(receiver);
        (uint256 totalScore, ) = locker.totalScore();

        ecoScore.updateUserEcoScoreInfo(sender);
        ecoScore.updateUserEcoScoreInfo(receiver);
        uint256 boostedSenderSupply = ecoScore.calculateEcoBoostedSupply(gToken, sender, senderScore, totalScore);
        uint256 boostedReceiverSupply = ecoScore.calculateEcoBoostedSupply(gToken, receiver, receiverScore, totalScore);
        dist.totalBoostedSupply = dist
            .totalBoostedSupply
            .add(boostedSenderSupply)
            .add(boostedReceiverSupply)
            .sub(senderInfo.boostedSupply)
            .sub(receiverInfo.boostedSupply);
        senderInfo.boostedSupply = boostedSenderSupply;
        receiverInfo.boostedSupply = boostedReceiverSupply;
    }

    /// @notice 토큰별로 소유하고 있는 보상 토큰을 모두 합하여 유저에게 전달
    /// @param markets gToken address
    /// @param account user address
    function claimGRV(address[] calldata markets, address account) external override onlyCore {
        require(account != address(0), "GRVDistributor: claimGRV: User account can't be zero address");
        require(taxTreasury != address(0), "GRVDistributor: claimGRV: TaxTreasury can't be zero address");
        uint256 amount = 0;
        uint256 userScore = locker.scoreOf(account);
        (uint256 totalScore, ) = locker.totalScore();

        for (uint256 i = 0; i < markets.length; i++) {
            amount = amount.add(_claimGRV(markets[i], account, userScore, totalScore));
        }
        require(amount > 0, "GRVDistributor: claimGRV: Can't claim amount of zero");
        (uint256 adjustedValue, uint256 taxAmount) = ecoScore.calculateClaimTaxes(account, amount);

        ecoScore.updateUserClaimInfo(account, amount);
        _updateAccountBoostedInfo(account);

        adjustedValue = Math.min(adjustedValue, IBEP20(GRV).balanceOf(address(this)));
        GRV.safeTransfer(account, adjustedValue);

        taxAmount = Math.min(taxAmount, IBEP20(GRV).balanceOf(address(this)));
        GRV.safeTransfer(taxTreasury, taxAmount);
        emit GRVClaimed(account, amount);
    }

    /// @notice 현재까지 쌓인 유저의 보상 GRV를 전부 재락업한다
    /// @dev GRV 재락업시 Claim tax와 Discount tax를 고려한 양만큼만 재락업한다.
    /// @param markets gToken address
    /// @param account user address
    function compound(address[] calldata markets, address account) external override onlyCore {
        require(account != address(0), "GRVDistributor: compound: User account can't be zero address");
        uint256 expiryOfAccount = locker.expiryOf(account);
        _compound(markets, account, expiryOfAccount, Constant.EcoScorePreviewOption.LOCK_MORE);
    }

    /// @notice 아직 GRV Lock한적이 없는 유저의 경우 쌓인 보상 GRV를 바로 Lock 할 수 있도록 하는 함수
    /// @param account user address
    function firstDeposit(address[] calldata markets, address account, uint256 expiry) external override onlyCore {
        require(account != address(0), "GRVDistributor: firstDeposit: User account can't be zero address");
        uint256 balanceOfLockedGrv = locker.balanceOf(account);
        require(balanceOfLockedGrv == 0, "GRVDistributor: firstDeposit: User already deposited");

        _compound(markets, account, expiry, Constant.EcoScorePreviewOption.LOCK);
    }

    /// @notice 특정 유저의 score가 0이 될 경우 해당 유저의 부스트 점수를 없애고 초기 담보량으로 업데이트한다.
    /// @param user user address
    function kick(address user) external override nonReentrant {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;
        _kick(user);
    }

    function kicks(address[] calldata users) external override nonReentrant {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;
        for (uint256 i = 0; i < users.length; i++) {
            _kick(users[i]);
        }
    }

    function _kick(address user) private {
        uint256 userScore = locker.scoreOf(user);
        require(userScore == 0, "GRVDistributor: kick not allowed");
        (uint256 totalScore, ) = locker.totalScore();

        address[] memory markets = core.allMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address market = markets[i];
            Constant.DistributionAccountInfo memory userInfo = accountDistributions[market][user];
            if (userInfo.boostedSupply > 0) _updateSupplyOf(market, user, userScore, totalScore);
            if (userInfo.boostedBorrow > 0) _updateBorrowOf(market, user, userScore, totalScore);
        }
        kickInfo[msg.sender] += 1;
    }

    /// @notice 유저가 locker에 deposit 후 boostedSupply, boostedBorrow 정보 업데이트를 위해 호출하는 함수
    /// @param user user address
    function updateAccountBoostedInfo(address user) external override {
        require(user != address(0), "GRVDistributor: compound: User account can't be zero address");
        _updateAccountBoostedInfo(user);
    }

    function updateAccountBoostedInfos(address[] calldata users) external override {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                _updateAccountBoostedInfo(users[i]);
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice 유저가 locker에 deposit 후 boostedSupply, boostedBorrow 정보 업데이트를 위해 호출하는 내부 함수
    /// @param user user address
    function _updateAccountBoostedInfo(address user) private {
        if (block.timestamp < LAUNCH_TIMESTAMP) return;

        uint256 userScore = locker.scoreOf(user);
        (uint256 totalScore, ) = locker.totalScore();
        ecoScore.updateUserEcoScoreInfo(user);

        address[] memory markets = core.allMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address market = markets[i];
            Constant.DistributionAccountInfo memory userInfo = accountDistributions[market][user];
            if (userInfo.boostedSupply > 0) _updateSupplyOf(market, user, userScore, totalScore);
            if (userInfo.boostedBorrow > 0) _updateBorrowOf(market, user, userScore, totalScore);
        }
    }

    /// @notice 축적된 보상 토큰 반환
    /// @dev time에 따라 그동안 축적된 보상 토큰 수량을 계산하여 반환한다
    /// @param market gToken address
    /// @param user user address
    function _accruedGRV(address market, address user) private view returns (uint256) {
        Constant.DistributionInfo memory dist = distributions[market];
        Constant.DistributionAccountInfo memory userInfo = accountDistributions[market][user];

        uint256 amount = userInfo.accruedGRV;
        uint256 accPerShareSupply = dist.accPerShareSupply;
        uint256 accPerShareBorrow = dist.accPerShareBorrow;

        uint256 timeElapsed = block.timestamp > dist.accruedAt ? block.timestamp.sub(dist.accruedAt) : 0;
        if (
            timeElapsed > 0 ||
            (accPerShareSupply != userInfo.accPerShareSupply) ||
            (accPerShareBorrow != userInfo.accPerShareBorrow)
        ) {
            if (dist.totalBoostedSupply > 0) {
                accPerShareSupply = accPerShareSupply.add(
                    dist.supplySpeed.mul(timeElapsed).mul(1e18).div(dist.totalBoostedSupply)
                );

                uint256 pendingGRV = userInfo.boostedSupply.mul(accPerShareSupply.sub(userInfo.accPerShareSupply)).div(
                    1e18
                );
                amount = amount.add(pendingGRV);
            }

            if (dist.totalBoostedBorrow > 0) {
                accPerShareBorrow = accPerShareBorrow.add(
                    dist.borrowSpeed.mul(timeElapsed).mul(1e18).div(dist.totalBoostedBorrow)
                );

                uint256 pendingGRV = userInfo.boostedBorrow.mul(accPerShareBorrow.sub(userInfo.accPerShareBorrow)).div(
                    1e18
                );
                amount = amount.add(pendingGRV);
            }
        }
        return amount;
    }

    /// @notice 유저의 축적된 보상 토큰 반환 및 0으로 초기화
    /// @dev time에 따라 그동안 축적된 보상 토큰수량을 계산하여 반환한다
    /// @param market gToken address
    /// @param user user address
    function _claimGRV(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) private returns (uint256 amount) {
        Constant.DistributionAccountInfo storage userInfo = accountDistributions[market][user];

        if (userInfo.boostedSupply > 0) _updateSupplyOf(market, user, userScore, totalScore);
        if (userInfo.boostedBorrow > 0) _updateBorrowOf(market, user, userScore, totalScore);

        amount = amount.add(userInfo.accruedGRV);
        userInfo.accruedGRV = 0;

        return amount;
    }

    /// @notice 특정 토큰의 담보 및 대출 APY 계산 후 반환
    /// @dev (담보스피드 X 365일 X 거버넌스토큰 가격 / 전체 담보 부스트 X 토큰 교환비 X 토큰가격 ) X 1e36
    /// @param market gToken address
    function _calculateMarketDistributionAPY(
        address market
    ) private view returns (uint256 apySupplyGRV, uint256 apyBorrowGRV) {
        uint256 decimals = _getDecimals(market);
        // base supply GRV APY == average supply GRV APY * (Total balance / total Boosted balance)
        // base supply GRV APY == (GRVRate * 365 days * price Of GRV) / (Total balance * exchangeRate * price of asset) * (Total balance / Total Boosted balance)
        // base supply GRV APY == (GRVRate * 365 days * price Of GRV) / (Total boosted balance * exchangeRate * price of asset)
        {
            uint256 numerSupply = distributions[market].supplySpeed.mul(365 days).mul(dashboard.getCurrentGRVPrice());
            uint256 denomSupply = distributions[market]
                .totalBoostedSupply
                .mul(10 ** (18 - decimals))
                .mul(IGToken(market).exchangeRate())
                .mul(priceCalculator.getUnderlyingPrice(market))
                .div(1e36);
            apySupplyGRV = denomSupply > 0 ? numerSupply.div(denomSupply) : 0;
        }

        // base borrow GRV APY == average borrow GRV APY * (Total balance / total Boosted balance)
        // base borrow GRV APY == (GRVRate * 365 days * price Of GRV) / (Total balance * exchangeRate * price of asset) * (Total balance / Total Boosted balance)
        // base borrow GRV APY == (GRVRate * 365 days * price Of GRV) / (Total boosted balance * exchangeRate * price of asset)
        {
            uint256 numerBorrow = distributions[market].borrowSpeed.mul(365 days).mul(dashboard.getCurrentGRVPrice());
            uint256 denomBorrow = distributions[market]
                .totalBoostedBorrow
                .mul(10 ** (18 - decimals))
                .mul(IGToken(market).getAccInterestIndex())
                .mul(priceCalculator.getUnderlyingPrice(market))
                .div(1e36);
            apyBorrowGRV = denomBorrow > 0 ? numerBorrow.div(denomBorrow) : 0;
        }
    }

    /// @notice 특정 토큰의 유저의 담보 및 대출 APY 계산 후 반환
    /// @dev
    /// @param market gToken address
    function _calculateAccountDistributionAPY(
        address market,
        address account
    ) private view returns (uint256 apyAccountSupplyGRV, uint256 apyAccountBorrowGRV) {
        if (account == address(0)) return (0, 0);
        (uint256 apySupplyGRV, uint256 apyBorrowGRV) = _calculateMarketDistributionAPY(market);

        // user supply GRV APY == ((GRVRate * 365 days * price Of GRV) / (Total boosted balance * exchangeRate * price of asset) ) * my boosted balance  / my balance
        uint256 accountSupply = IGToken(market).balanceOf(account);
        apyAccountSupplyGRV = accountSupply > 0
            ? apySupplyGRV.mul(accountDistributions[market][account].boostedSupply).div(accountSupply)
            : 0;

        // user borrow GRV APY == (GRVRate * 365 days * price Of GRV) / (Total boosted balance * interestIndex * price of asset) * my boosted balance  / my balance
        uint256 accountBorrow = IGToken(market).borrowBalanceOf(account).mul(1e18).div(
            IGToken(market).getAccInterestIndex()
        );

        if (IGToken(market).underlying() == address(0)) {
            uint256 nftAccInterestIndex = lendPoolLoan.getAccInterestIndex();
            accountBorrow = accountBorrow.add(
                lendPoolLoan.userBorrowBalance(account).mul(1e18).div(nftAccInterestIndex)
            );
        }

        apyAccountBorrowGRV = accountBorrow > 0
            ? apyBorrowGRV.mul(accountDistributions[market][account].boostedBorrow).div(accountBorrow)
            : 0;
    }

    /// @notice kick, Claim용 update supply
    /// @dev user score가 0인 경우 boostedSupply 값을 초기 담보금으로 업데이트 하기 위함
    /// @param market gToken address
    function _updateSupplyOf(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) private updateDistributionOf(market) {
        Constant.DistributionInfo storage dist = distributions[market];
        Constant.DistributionAccountInfo storage userInfo = accountDistributions[market][user];

        if (userInfo.boostedSupply > 0) {
            uint256 accGRVPerShare = dist.accPerShareSupply.sub(userInfo.accPerShareSupply);
            userInfo.accruedGRV = userInfo.accruedGRV.add(accGRVPerShare.mul(userInfo.boostedSupply).div(1e18));
        }
        userInfo.accPerShareSupply = dist.accPerShareSupply;

        uint256 boostedSupply = ecoScore.calculateEcoBoostedSupply(market, user, userScore, totalScore);
        dist.totalBoostedSupply = dist.totalBoostedSupply.add(boostedSupply).sub(userInfo.boostedSupply);
        userInfo.boostedSupply = boostedSupply;
    }

    function _updateBorrowOf(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) private updateDistributionOf(market) {
        Constant.DistributionInfo storage dist = distributions[market];
        Constant.DistributionAccountInfo storage userInfo = accountDistributions[market][user];

        if (userInfo.boostedBorrow > 0) {
            uint256 accGRVPerShare = dist.accPerShareBorrow.sub(userInfo.accPerShareBorrow);
            userInfo.accruedGRV = userInfo.accruedGRV.add(accGRVPerShare.mul(userInfo.boostedBorrow).div(1e18));
        }
        userInfo.accPerShareBorrow = dist.accPerShareBorrow;

        uint256 boostedBorrow = ecoScore.calculateEcoBoostedBorrow(market, user, userScore, totalScore);
        dist.totalBoostedBorrow = dist.totalBoostedBorrow.add(boostedBorrow).sub(userInfo.boostedBorrow);
        userInfo.boostedBorrow = boostedBorrow;
    }

    function _compound(
        address[] calldata markets,
        address account,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) private {
        require(taxTreasury != address(0), "GRVDistributor: _compound: TaxTreasury can't be zero address");
        uint256 amount = 0;
        uint256 userScore = locker.scoreOf(account);
        (uint256 totalScore, ) = locker.totalScore();

        for (uint256 i = 0; i < markets.length; i++) {
            amount = amount.add(_claimGRV(markets[i], account, userScore, totalScore));
        }
        (uint256 adjustedValue, uint256 taxAmount) = ecoScore.calculateCompoundTaxes(account, amount, expiry, option);

        locker.depositBehalf(account, adjustedValue, expiry);
        ecoScore.updateUserCompoundInfo(account, adjustedValue);

        taxAmount = Math.min(taxAmount, IBEP20(GRV).balanceOf(address(this)));
        if (taxAmount > 0) {
            GRV.safeTransfer(taxTreasury, taxAmount);
        }

        emit GRVCompound(account, amount, adjustedValue, taxAmount, expiry);
    }

    function _getDecimals(address gToken) internal view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18;
            // ETH
        } else {
            decimals = IBEP20(underlying).decimals();
        }
    }
}

