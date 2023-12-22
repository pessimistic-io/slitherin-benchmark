// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";
import "./SafeMath.sol";
import "./SafeToken.sol";
import "./WhitelistUpgradeable.sol";
import "./IEcoScore.sol";
import "./IGToken.sol";
import "./ILocker.sol";
import "./IGRVDistributor.sol";
import "./IPriceProtectionTaxCalculator.sol";
import "./IPriceCalculator.sol";
import "./ILendPoolLoan.sol";

contract EcoScore is IEcoScore, WhitelistUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant BOOST_PORTION = 100; //1배
    uint256 public constant BOOST_MAX = 200; // 기본 max boost 2배
    uint256 private constant ECO_BOOST_PORTION = 100; // 1배
    uint256 private constant TAX_DEFAULT = 0; // 0% default tax
    uint256 private constant MAX_BOOST_MULTIPLE_VALUE = 1000; // 10%
    uint256 private constant MAX_BOOST_CAP_VALUE = 1000; // 10%
    uint256 private constant MAX_BOOST_BASE_VALUE = 1000; // 10%
    uint256 private constant MAX_REDEEM_FEE_VALUE = 1000; // 10%
    uint256 private constant MAX_CLAIM_TAX_VALUE = 100; // 100%

    /* ========== STATE VARIABLES ========== */

    ILocker public locker;
    IGRVDistributor public grvDistributor;
    IPriceProtectionTaxCalculator public priceProtectionTaxCalculator;
    IPriceCalculator public priceCalculator;
    ILendPoolLoan public lendPoolLoan;
    address public GRV;

    mapping(address => Constant.EcoScoreInfo) public accountEcoScoreInfo; // 유저별 eco score 정보
    mapping(Constant.EcoZone => Constant.EcoPolicyInfo) public ecoPolicyInfo; // zone 별 tax 및 파라미터 정보 저장
    mapping(address => Constant.EcoPolicyInfo) private _customEcoPolicyRate;
    mapping(address => bool) private _hasCustomTax;
    mapping(address => bool) private _isExcluded;

    address[] private _excluded;

    Constant.EcoZoneStandard public ecoZoneStandard;
    Constant.PPTPhaseInfo public pptPhaseInfo;

    /* ========== VARIABLE GAP ========== */

    uint256[49] private __gap;

    /* ========== MODIFIERS ========== */

    /// @dev msg.sender 가 core address 인지 검증
    modifier onlyGRVDistributor() {
        require(msg.sender == address(grvDistributor), "EcoScore: caller is not grvDistributor");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize(
        address _grvDistributor,
        address _locker,
        address _priceProtectionTaxCalculator,
        address _priceCalculator,
        address _grvTokenAddress
    ) external initializer {
        require(_grvDistributor != address(0), "EcoScore: grvDistributor can't be zero address");
        require(_locker != address(0), "EcoScore: locker can't be zero address");
        require(
            _priceProtectionTaxCalculator != address(0),
            "EcoScore: priceProtectionTaxCalculator can't be zero address"
        );
        require(_priceCalculator != address(0), "EcoScore: priceCalculator address can't be zero");
        require(_grvTokenAddress != address(0), "EcoScore: grv address can't be zero");

        __WhitelistUpgradeable_init();
        grvDistributor = IGRVDistributor(_grvDistributor);
        locker = ILocker(_locker);
        priceProtectionTaxCalculator = IPriceProtectionTaxCalculator(_priceProtectionTaxCalculator);
        priceCalculator = IPriceCalculator(_priceCalculator);
        GRV = _grvTokenAddress;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice grvDistributor 변경
    /// @dev owner address 에서만 요청 가능
    /// @param _grvDistributor 새로운 grvDistributor address
    function setGRVDistributor(address _grvDistributor) external override onlyOwner {
        require(_grvDistributor != address(0), "EcoScore: invalid grvDistributor address");
        grvDistributor = IGRVDistributor(_grvDistributor);
        emit SetGRVDistributor(_grvDistributor);
    }

    /// @notice priceProtectionTaxCalculator 변경
    /// @dev owner address 에서만 요청 가능
    /// @param _priceProtectionTaxCalculator 새로운 priceProtectionTaxCalculator address
    function setPriceProtectionTaxCalculator(address _priceProtectionTaxCalculator) external override onlyOwner {
        require(_priceProtectionTaxCalculator != address(0), "EcoScore: invalid priceProtectionTaxCalculator address");
        priceProtectionTaxCalculator = IPriceProtectionTaxCalculator(_priceProtectionTaxCalculator);
        emit SetPriceProtectionTaxCalculator(_priceProtectionTaxCalculator);
    }

    /// @notice priceCalculator address 를 설정
    /// @dev ZERO ADDRESS 로 설정할 수 없음
    /// @param _priceCalculator priceCalculator contract address
    function setPriceCalculator(address _priceCalculator) external override onlyOwner {
        require(_priceCalculator != address(0), "EcoScore: invalid priceCalculator address");
        priceCalculator = IPriceCalculator(_priceCalculator);

        emit SetPriceCalculator(_priceCalculator);
    }

    function setLendPoolLoan(address _lendPoolLoan) external override onlyOwner {
        require(_lendPoolLoan != address(0), "EcoScore: invalid lendPoolLoan address");
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);

        emit SetLendPoolLoan(_lendPoolLoan);
    }

    function setEcoPolicyInfo(
        Constant.EcoZone _zone,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] calldata _pptTax
    ) external override onlyOwner {
        require(
            _zone == Constant.EcoZone.GREEN ||
                _zone == Constant.EcoZone.LIGHTGREEN ||
                _zone == Constant.EcoZone.YELLOW ||
                _zone == Constant.EcoZone.ORANGE ||
                _zone == Constant.EcoZone.RED,
            "EcoScore: setEcoPolicyInfo: invalid zone"
        );
        require(
            _boostMultiple > 0 && _boostMultiple <= MAX_BOOST_MULTIPLE_VALUE,
            "EcoScore: setEcoPolicyInfo: invalid boostMultiple"
        );
        require(
            _maxBoostCap > 0 && _maxBoostCap <= MAX_BOOST_CAP_VALUE,
            "EcoScore: setEcoPolicyInfo: invalid maxBoostCap"
        );
        require(_boostBase >= 0 && _boostBase <= MAX_BOOST_BASE_VALUE, "EcoScore: setEcoPolicyInfo: invalid boostBase");
        require(_redeemFee > 0 && _redeemFee <= MAX_REDEEM_FEE_VALUE, "EcoScore: setEcoPolicyInfo: invalid redeemFee");
        require(_claimTax >= 0 && _claimTax <= MAX_CLAIM_TAX_VALUE, "EcoScore: setEcoPolicyInfo: invalid claimTax");
        require(_pptTax.length == 4, "EcoScore: setEcoPolicyInfo: invalid pptTax");

        ecoPolicyInfo[_zone].boostMultiple = _boostMultiple;
        ecoPolicyInfo[_zone].maxBoostCap = _maxBoostCap;
        ecoPolicyInfo[_zone].boostBase = _boostBase;
        ecoPolicyInfo[_zone].redeemFee = _redeemFee;
        ecoPolicyInfo[_zone].claimTax = _claimTax;
        ecoPolicyInfo[_zone].pptTax = _pptTax;

        emit SetEcoPolicyInfo(_zone, _boostMultiple, _maxBoostCap, _boostBase, _redeemFee, _claimTax, _pptTax);
    }

    function setEcoZoneStandard(
        uint256 _minExpiryOfGreenZone,
        uint256 _minExpiryOfLightGreenZone,
        uint256 _minDrOfGreenZone,
        uint256 _minDrOfLightGreenZone,
        uint256 _minDrOfYellowZone,
        uint256 _minDrOfOrangeZone
    ) external override onlyOwner {
        require(
            _minExpiryOfGreenZone >= 4 weeks && _minExpiryOfGreenZone <= 2 * 365 days,
            "EcoScore: setEcoZoneStandard: invalid minExpiryOfGreenZone"
        );
        require(
            _minExpiryOfLightGreenZone >= 4 weeks && _minExpiryOfLightGreenZone <= 2 * 365 days,
            "EcoScore: setEcoZoneStandard: invalid minExpiryOfLightGreenZone"
        );

        require(
            _minDrOfGreenZone >= 0 && _minDrOfGreenZone <= 100,
            "EcoScore: setEcoZoneStandard: invalid minDrOfGreenZone"
        );
        require(
            _minDrOfLightGreenZone >= 0 && _minDrOfLightGreenZone <= 100,
            "EcoScore: setEcoZoneStandard: invalid minDrOfLightGreenZone"
        );
        require(
            _minDrOfYellowZone >= 0 && _minDrOfYellowZone <= 100,
            "EcoScore: setEcoZoneStandard: invalid minDrOfYellowZone"
        );
        require(
            _minDrOfOrangeZone >= 0 && _minDrOfOrangeZone <= 100,
            "EcoScore: setEcoZoneStandard: invalid minDrOfOrangeZone"
        );
        require(
            _minDrOfGreenZone >= _minDrOfLightGreenZone &&
                _minDrOfLightGreenZone >= _minDrOfYellowZone &&
                _minDrOfYellowZone >= _minDrOfOrangeZone,
            "EcoScore: setEcoZoneStandard: invalid order of zone"
        );

        ecoZoneStandard.minExpiryOfGreenZone = _minExpiryOfGreenZone;
        ecoZoneStandard.minExpiryOfLightGreenZone = _minExpiryOfLightGreenZone;

        ecoZoneStandard.minDrOfGreenZone = _minDrOfGreenZone;
        ecoZoneStandard.minDrOfLightGreenZone = _minDrOfLightGreenZone;
        ecoZoneStandard.minDrOfYellowZone = _minDrOfYellowZone;
        ecoZoneStandard.minDrOfOrangeZone = _minDrOfOrangeZone;
        emit SetEcoZoneStandard(
            _minExpiryOfGreenZone,
            _minExpiryOfLightGreenZone,
            _minDrOfGreenZone,
            _minDrOfLightGreenZone,
            _minDrOfYellowZone,
            _minDrOfOrangeZone
        );
    }

    function setPPTPhaseInfo(
        uint256 _phase1,
        uint256 _phase2,
        uint256 _phase3,
        uint256 _phase4
    ) external override onlyOwner {
        require(_phase1 >= 0 && _phase1 < 100, "EcoScore: setPPTPhaseInfo: invalid phase1 standard");
        require(_phase2 > _phase1 && _phase2 < 100, "EcoScore: setPPTPhaseInfo: invalid phase2 standard");
        require(_phase3 > _phase2 && _phase3 < 100, "EcoScore: setPPTPhaseInfo: invalid phase3 standard");
        require(_phase4 > _phase3 && _phase4 < 100, "EcoScore: setPPTPhaseInfo: invalid phase4 standard");

        pptPhaseInfo.phase1 = _phase1;
        pptPhaseInfo.phase2 = _phase2;
        pptPhaseInfo.phase3 = _phase3;
        pptPhaseInfo.phase4 = _phase4;

        emit SetPPTPhaseInfo(_phase1, _phase2, _phase3, _phase4);
    }

    function setAccountCustomEcoPolicy(
        address account,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] calldata _pptTax
    ) external override onlyOwner {
        require(account != address(0), "EcoScore: setAccountCustomTax: Invalid account");
        require(
            _boostMultiple > 0 && _boostMultiple <= MAX_BOOST_MULTIPLE_VALUE,
            "EcoScore: setAccountCustomTax: Invalid boostMultiple"
        );
        require(
            _maxBoostCap > 0 && _maxBoostCap <= MAX_BOOST_CAP_VALUE,
            "EcoScore: setAccountCustomTax: Invalid maxBoostCap"
        );
        require(
            _boostBase >= 0 && _boostBase <= MAX_BOOST_BASE_VALUE,
            "EcoScore: setAccountCustomTax: Invalid boostBase"
        );
        require(
            _redeemFee > 0 && _redeemFee <= MAX_REDEEM_FEE_VALUE,
            "EcoScore: setAccountCustomTax: Invalid redeemFee"
        );
        require(_claimTax >= 0 && _claimTax <= MAX_CLAIM_TAX_VALUE, "EcoScore: setAccountCustomTax: Invalid claimTax");
        require(_pptTax.length == 4, "EcoScore: setAccountCustomTax: Invalid pptTax");

        _hasCustomTax[account] = true;

        _customEcoPolicyRate[account].boostMultiple = _boostMultiple;
        _customEcoPolicyRate[account].maxBoostCap = _maxBoostCap;
        _customEcoPolicyRate[account].boostBase = _boostBase;
        _customEcoPolicyRate[account].redeemFee = _redeemFee;
        _customEcoPolicyRate[account].claimTax = _claimTax;
        _customEcoPolicyRate[account].pptTax = _pptTax;

        emit SetAccountCustomEcoPolicy(
            account,
            _boostMultiple,
            _maxBoostCap,
            _boostBase,
            _redeemFee,
            _claimTax,
            _pptTax
        );
    }

    function removeAccountCustomEcoPolicy(address account) external override onlyOwner {
        require(account != address(0), "EcoScore: removeAccountCustomTax: Invalid account");
        _hasCustomTax[account] = false;

        emit RemoveAccountCustomEcoPolicy(account);
    }

    function excludeAccount(address account) external override onlyOwner {
        require(account != address(0), "EcoScore: excludeAccount: Invalid account");
        require(!_isExcluded[account], "EcoScore: excludeAccount: Account is already excluded");
        _isExcluded[account] = true;
        _excluded.push(account);

        emit ExcludeAccount(account);
    }

    function includeAccount(address account) external override onlyOwner {
        require(_isExcluded[account], "EcoScore: includeAccount: Account is not excluded before");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _isExcluded[account] = false;
                delete _excluded[_excluded.length - 1];
                break;
            }
        }
        emit IncludeAccount(account);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice 현재까지의 누적 claim grv에 따른 user의 DR 및 Zone 업데이트
    /// @param account user address
    function updateUserEcoScoreInfo(address account) external override onlyGRVDistributor {
        require(account != address(0), "EcoScore: updateUserEcoScoreInfo: Invalid account");
        uint256 userScore = locker.scoreOf(account);
        uint256 remainExpiry = locker.remainExpiryOf(account);
        uint256 numerator = userScore > accountEcoScoreInfo[account].claimedGrv.div(2)
            ? userScore.sub(accountEcoScoreInfo[account].claimedGrv.div(2))
            : 0;
        uint256 ecoDR = userScore > 0 ? numerator.mul(1e18).div(userScore) : 0;
        uint256 ecoDRpercent = ecoDR.mul(100).div(1e18);

        Constant.EcoZone ecoZone = _getEcoZone(ecoDRpercent, remainExpiry);

        Constant.EcoZone prevZone = accountEcoScoreInfo[account].ecoZone;

        if (prevZone != ecoZone) {
            accountEcoScoreInfo[account].ecoZone = ecoZone;
            accountEcoScoreInfo[account].changedEcoZoneAt = block.timestamp;
        }
        accountEcoScoreInfo[account].ecoDR = ecoDR;
    }

    /// @notice Claim시 User의 claimedGRV 정보 업데이트
    function updateUserClaimInfo(address account, uint256 amount) external override onlyWhitelisted {
        accountEcoScoreInfo[account].claimedGrv += amount;
    }

    /// @notice Compound시 User의 compoundGRV 정보 업데이트
    function updateUserCompoundInfo(address account, uint256 amount) external override onlyWhitelisted {
        accountEcoScoreInfo[account].compoundGrv += amount;
    }

    /* ========== VIEWS ========== */
    /// @notice user의 eco score 정보 전달
    /// @param account user address
    function accountEcoScoreInfoOf(address account) external view override returns (Constant.EcoScoreInfo memory) {
        return accountEcoScoreInfo[account];
    }

    /// @notice 특정 zone의 boost parameter 정보 전달
    /// @param zone zone name
    function ecoPolicyInfoOf(Constant.EcoZone zone) external view override returns (Constant.EcoPolicyInfo memory) {
        require(
            zone == Constant.EcoZone.GREEN ||
                zone == Constant.EcoZone.LIGHTGREEN ||
                zone == Constant.EcoZone.YELLOW ||
                zone == Constant.EcoZone.ORANGE ||
                zone == Constant.EcoZone.RED,
            "EcoScore: ecoPolicyInfoOf: invalid zone"
        );
        return ecoPolicyInfo[zone];
    }

    /// @notice 해당 토큰에서의 유저의 boost된 담보량 반환
    /// @dev Eco score 를 적용한 boostedSupply 계산 함수
    /// @param market gToken address
    /// @param user user address
    /// @param userScore user veToken score
    /// @param totalScore total veToken score
    function calculateEcoBoostedSupply(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) external view override returns (uint256) {
        uint256 defaultSupply = IGToken(market).balanceOf(user);
        uint256 boostedSupply = defaultSupply;

        Constant.BoostConstant memory boostConstant = _getBoostConstant(user);

        if (userScore > 0 && totalScore > 0) {
            uint256 totalSupply = IGToken(market).totalSupply();
            uint256 scoreBoosted = _calculateScoreBoosted(totalSupply, userScore, totalScore, boostConstant);

            boostedSupply = boostedSupply.add(scoreBoosted);
        }
        return Math.min(boostedSupply, defaultSupply.mul(boostConstant.boost_max).div(100));
    }

    /// @notice 해당 토큰에서의 유저의 boost된 대출금 반환
    /// @param market gToken address
    /// @param user user address
    /// @param userScore user veToken score
    /// @param totalScore total veToken score
    function calculateEcoBoostedBorrow(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) external view override returns (uint256) {
        uint256 accInterestIndex = IGToken(market).getAccInterestIndex();
        uint256 defaultBorrow = IGToken(market).borrowBalanceOf(user).mul(1e18).div(accInterestIndex);

        if (IGToken(market).underlying() == address(0)) {
            uint256 nftAccInterestIndex = lendPoolLoan.getAccInterestIndex();
            uint256 nftBorrow = lendPoolLoan.userBorrowBalance(user).mul(1e18).div(nftAccInterestIndex);
            defaultBorrow = defaultBorrow.add(nftBorrow);
        }

        uint256 boostedBorrow = defaultBorrow;
        Constant.BoostConstant memory boostConstant = _getBoostConstant(user);

        if (userScore > 0 && totalScore > 0) {
            uint256 totalBorrow = IGToken(market).totalBorrow().mul(1e18).div(accInterestIndex);
            uint256 scoreBoosted = _calculateScoreBoosted(totalBorrow, userScore, totalScore, boostConstant);
            boostedBorrow = boostedBorrow.add(scoreBoosted);
        }
        return Math.min(boostedBorrow, defaultBorrow.mul(boostConstant.boost_max).div(100));
    }

    /// @notice 유저의 Eco score에 따른 세금 비율을 구한뒤 적용하여 실수령금액 및 세금액 반환
    /// @dev 해당 amount만큼 Claim 됐을 시의 변경될 ecoZone을 미리 구한 뒤 해당 ecoZone의 claimTax 및 pptTax를 이용하여 tax 차감
    /// @param account user address
    /// @param value grv amount
    function calculateClaimTaxes(
        address account,
        uint256 value
    ) external view override returns (uint256 adjustedValue, uint256 taxAmount) {
        adjustedValue = value;
        (Constant.EcoZone userPreEcoZone, , ) = _calculatePreUserEcoScoreInfo(
            account,
            value,
            0,
            Constant.EcoScorePreviewOption.CLAIM
        );
        uint256 claimTaxPercent = _getClaimTaxRate(account, userPreEcoZone);
        (uint256 pptTaxPercent, ) = _getPptTaxRate(userPreEcoZone);
        uint256 taxPercent = claimTaxPercent.add(pptTaxPercent);

        if (taxPercent > 0) {
            (adjustedValue, taxAmount) = _calculateTransactionTax(value, taxPercent);
        }
        return (adjustedValue, taxAmount);
    }

    /// @notice 유저의 변경할 GRV수량과 expiry 따른 eco score를 미리 계산하여 사전 tax정보를 반환
    /// @param account user address
    /// @param value grv amount
    /// @param expiry lock exiry date
    /// @param option 0 = lock, 1 = claim, 2 = extend, 3 = lock more
    function getClaimTaxRate(
        address account,
        uint256 value,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (uint256) {
        (Constant.EcoZone userPreEcoZone, , ) = _calculatePreUserEcoScoreInfo(account, value, expiry, option);
        return _getClaimTaxRate(account, userPreEcoZone);
    }

    /// @notice 유저의 expiry에 따른 할인율 반환
    /// @dev 남은 expiry기간 / 2년 X 100
    /// @param account user address
    function getDiscountTaxRate(address account) external view override returns (uint256) {
        return _getDiscountTaxRate(account);
    }

    /// @notice 유저의 EcoScore 혹은 전달받은 ecoZone에 따른 ppt tax 반환
    /// @param ecoZone user's ecoZone
    function getPptTaxRate(
        Constant.EcoZone ecoZone
    ) external view override returns (uint256 pptTaxRate, uint256 gapPercent) {
        return _getPptTaxRate(ecoZone);
    }

    /// @notice 유저의 Eco score에 따른 세금 비율을 구한뒤 적용하여 실수령금액 및 세금액 반환
    /// @dev 해당 amount만큼 Compound 됐을 시의 변경될 ecoZone을 미리 구한 뒤 해당 ecoZone의 claimTax 및 pptTax를 이용하여 tax 차감
    function calculateCompoundTaxes(
        address account,
        uint256 value,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (uint256 adjustedValue, uint256 taxAmount) {
        adjustedValue = value;
        (Constant.EcoZone userPreEcoZone, , ) = _calculatePreUserEcoScoreInfo(account, value, expiry, option);
        uint256 claimTaxPercent = _getClaimTaxRate(account, userPreEcoZone);
        (uint256 pptTaxPercent, ) = _getPptTaxRate(userPreEcoZone);
        uint256 discountTaxPercent = _getDiscountTaxRate(account);

        uint256 penaltyTax = claimTaxPercent.add(pptTaxPercent);
        uint256 finalTax = penaltyTax > discountTaxPercent ? SafeMath.sub(penaltyTax, discountTaxPercent) : 0;

        if (finalTax > 0) {
            (adjustedValue, taxAmount) = _calculateTransactionTax(value, finalTax);
        }
        return (adjustedValue, taxAmount);
    }

    /// @notice 유저가 사전에 자신의 액션에 따른 zone 변경정보를 미리 확인하기 위한 함수
    /// @param account user address
    /// @param amount request amount
    /// @param expiry request expiry
    /// @param option 0 = lock, 1 = claim, 2 = extend, 3 = lock more
    function calculatePreUserEcoScoreInfo(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (Constant.EcoZone ecoZone, uint256 ecoDR, uint256 userScore) {
        (ecoZone, ecoDR, userScore) = _calculatePreUserEcoScoreInfo(account, amount, expiry, option);
    }

    /// @notice eco zone 구하는 함수
    function getEcoZone(
        uint256 ecoDRpercent,
        uint256 remainExpiry
    ) external view override returns (Constant.EcoZone ecoZone) {
        return _getEcoZone(ecoDRpercent, remainExpiry);
    }

    /// @notice 전달받은 ecoZone으로 계산시의 Boosted된 supply 양을 반환
    /// @dev 예상 boostedSupply를 계산하기 위해 사용
    function calculatePreEcoBoostedSupply(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore,
        Constant.EcoZone ecoZone
    ) external view override returns (uint256) {
        uint256 defaultSupply = IGToken(market).balanceOf(user);
        uint256 boostedSupply = defaultSupply;
        Constant.BoostConstant memory boostConstant = _getPreBoostConstant(user, ecoZone);

        if (userScore > 0 && totalScore > 0) {
            uint256 totalSupply = IGToken(market).totalSupply();
            uint256 scoreBoosted = _calculateScoreBoosted(totalSupply, userScore, totalScore, boostConstant);

            boostedSupply = boostedSupply.add(scoreBoosted);
        }
        return Math.min(boostedSupply, defaultSupply.mul(boostConstant.boost_max).div(100));
    }

    /// @notice 전달받은 ecoZone으로 계산시의 Boosted된 borrow 양을 반환
    /// @dev 예상 boostedBorrow를 계산하기 위해 사용
    function calculatePreEcoBoostedBorrow(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore,
        Constant.EcoZone ecoZone
    ) external view override returns (uint256) {
        uint256 accInterestIndex = IGToken(market).getAccInterestIndex();
        uint256 defaultBorrow = IGToken(market).borrowBalanceOf(user).mul(1e18).div(accInterestIndex);

        if (IGToken(market).underlying() == address(0)) {
            uint256 nftAccInterestIndex = lendPoolLoan.getAccInterestIndex();
            uint256 nftBorrow = lendPoolLoan.userBorrowBalance(user).mul(1e18).div(nftAccInterestIndex);
            defaultBorrow = defaultBorrow.add(nftBorrow);
        }

        uint256 boostedBorrow = defaultBorrow;
        Constant.BoostConstant memory boostConstant = _getPreBoostConstant(user, ecoZone);

        if (userScore > 0 && totalScore > 0) {
            uint256 totalBorrow = IGToken(market).totalBorrow().mul(1e18).div(accInterestIndex);
            uint256 scoreBoosted = _calculateScoreBoosted(totalBorrow, userScore, totalScore, boostConstant);
            boostedBorrow = boostedBorrow.add(scoreBoosted);
        }
        return Math.min(boostedBorrow, defaultBorrow.mul(boostConstant.boost_max).div(100));
    }

    /* ========== PRIVATE FUNCTIONS ========== */
    /// @notice BoostedSupply or BoostedBorrow 계산에 필요한 상수값들을 user의 zone에 따라 결정하여 반환
    /// @param user user address
    function _getBoostConstant(address user) private view returns (Constant.BoostConstant memory) {
        Constant.BoostConstant memory boostConstant;

        if (_hasCustomTax[user]) {
            boostConstant.boost_max = _customEcoPolicyRate[user].maxBoostCap;
            boostConstant.boost_portion = _customEcoPolicyRate[user].boostBase;
            boostConstant.ecoBoost_portion = _customEcoPolicyRate[user].boostMultiple;
        } else {
            Constant.EcoPolicyInfo storage userEcoPolicyInfo = ecoPolicyInfo[accountEcoScoreInfo[user].ecoZone];
            boostConstant.boost_max = userEcoPolicyInfo.maxBoostCap;
            boostConstant.boost_portion = userEcoPolicyInfo.boostBase;
            boostConstant.ecoBoost_portion = userEcoPolicyInfo.boostMultiple;
        }
        return boostConstant;
    }

    /// @notice BoostedSupply or BoostedBorrow 계산에 필요한 상수값들을 전달받은 zone에 따라 결정하여 반환
    /// @param user user address
    /// @param ecoZone expected ecoZone
    function _getPreBoostConstant(
        address user,
        Constant.EcoZone ecoZone
    ) private view returns (Constant.BoostConstant memory) {
        Constant.BoostConstant memory boostConstant;

        if (_hasCustomTax[user]) {
            boostConstant.boost_max = _customEcoPolicyRate[user].maxBoostCap;
            boostConstant.boost_portion = _customEcoPolicyRate[user].boostBase;
            boostConstant.ecoBoost_portion = _customEcoPolicyRate[user].boostMultiple;
        } else {
            Constant.EcoPolicyInfo storage userEcoPolicyInfo = ecoPolicyInfo[ecoZone];
            boostConstant.boost_max = userEcoPolicyInfo.maxBoostCap;
            boostConstant.boost_portion = userEcoPolicyInfo.boostBase;
            boostConstant.ecoBoost_portion = userEcoPolicyInfo.boostMultiple;
        }
        return boostConstant;
    }

    /// @notice DefaultSupply or DefaultBorrow에서 자신의 eco score에 따른 가중치 적용하여 Boosted 값 반환
    /// @param totalAmount DefaultSupply or DefaultBorrow에서
    /// @param userScore user's veGRV
    /// @param totalScore total veGRV
    function _calculateScoreBoosted(
        uint256 totalAmount,
        uint256 userScore,
        uint256 totalScore,
        Constant.BoostConstant memory boostConstant
    ) private pure returns (uint256) {
        uint256 scoreBoosted = totalAmount
            .mul(userScore)
            .div(totalScore)
            .mul(boostConstant.boost_portion)
            .mul(boostConstant.ecoBoost_portion)
            .div(10000);

        return scoreBoosted;
    }

    /// @notice 전달받은 세금을 적용하여 실수령액과 세금액 반환
    function _calculateTransactionTax(
        uint256 value,
        uint256 tax
    ) private pure returns (uint256 adjustedValue, uint256 taxAmount) {
        taxAmount = tax < 100 ? value.mul(tax).div(100) : value;
        adjustedValue = tax < 100 ? value.mul(SafeMath.sub(100, tax)).div(100) : 0;
        return (adjustedValue, taxAmount);
    }

    /// @notice DR percent에 따른 eco zone 반환
    function _getEcoZone(uint256 ecoDRpercent, uint256 remainExpiry) private view returns (Constant.EcoZone ecoZone) {
        require(
            ecoZoneStandard.minExpiryOfGreenZone >= 4 weeks && ecoZoneStandard.minExpiryOfGreenZone <= 2 * 365 days,
            "EcoScore: setEcoZoneStandard: invalid minExpiryOfGreenZone"
        );
        require(
            ecoZoneStandard.minExpiryOfLightGreenZone >= 4 weeks &&
                ecoZoneStandard.minExpiryOfLightGreenZone <= 2 * 365 days,
            "EcoScore: setEcoZoneStandard: invalid minExpiryOfLightGreenZone"
        );
        require(
            ecoZoneStandard.minDrOfGreenZone >= 0 && ecoZoneStandard.minDrOfGreenZone <= 100,
            "EcoScore: _getEcoZone: invalid minDrOfGreenZone"
        );
        require(
            ecoZoneStandard.minDrOfLightGreenZone >= 0 && ecoZoneStandard.minDrOfLightGreenZone <= 100,
            "EcoScore: _getEcoZone: invalid minDrOfLightGreenZone"
        );
        require(
            ecoZoneStandard.minDrOfYellowZone >= 0 && ecoZoneStandard.minDrOfYellowZone <= 100,
            "EcoScore: _getEcoZone: invalid minDrOfYellowZone"
        );
        require(
            ecoZoneStandard.minDrOfOrangeZone >= 0 && ecoZoneStandard.minDrOfOrangeZone <= 100,
            "EcoScore: _getEcoZone: invalid minDrOfOrangeZone"
        );

        if (ecoDRpercent > ecoZoneStandard.minDrOfGreenZone && remainExpiry >= ecoZoneStandard.minExpiryOfGreenZone) {
            ecoZone = Constant.EcoZone.GREEN;
        } else if (
            ecoDRpercent > ecoZoneStandard.minDrOfLightGreenZone &&
            remainExpiry >= ecoZoneStandard.minExpiryOfLightGreenZone
        ) {
            ecoZone = Constant.EcoZone.LIGHTGREEN;
        } else if (ecoDRpercent > ecoZoneStandard.minDrOfYellowZone) {
            ecoZone = Constant.EcoZone.YELLOW;
        } else if (ecoDRpercent > ecoZoneStandard.minDrOfOrangeZone) {
            ecoZone = Constant.EcoZone.ORANGE;
        } else {
            ecoZone = Constant.EcoZone.RED;
        }
    }

    /// @notice 전달받은 유저 정보 및 lock 정보에 따라 변화될 예상 EcoScore Info를 반환
    function _calculatePreUserEcoScoreInfo(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) private view returns (Constant.EcoZone ecoZone, uint256 ecoDR, uint256 userScore) {
        uint256 preClaimedGrv = 0;
        uint256 remainExpiry = locker.remainExpiryOf(account);

        if (option == Constant.EcoScorePreviewOption.CLAIM) {
            userScore = locker.scoreOf(account);
            preClaimedGrv = (accountEcoScoreInfo[account].claimedGrv).add(amount);
        } else {
            userScore = locker.preScoreOf(account, amount, expiry, option);
            preClaimedGrv = accountEcoScoreInfo[account].claimedGrv;
            remainExpiry = locker.preRemainExpiryOf(expiry);
        }
        preClaimedGrv = preClaimedGrv.div(2);
        uint256 numerator = userScore > preClaimedGrv ? userScore.sub(preClaimedGrv) : 0;
        ecoDR = userScore > 0 ? numerator.mul(1e18).div(userScore) : 0;
        uint256 ecoDRpercent = ecoDR.mul(100).div(1e18);
        ecoZone = _getEcoZone(ecoDRpercent, remainExpiry);
    }

    /// @notice 유저와 전달받은 ecoZone의 정보에 따른 claimTax값을 반환한다
    function _getClaimTaxRate(address account, Constant.EcoZone userEcoZone) private view returns (uint256) {
        uint256 taxPercent = TAX_DEFAULT; // set to default tax 0%
        if (!_isExcluded[account]) {
            if (_hasCustomTax[account]) {
                taxPercent = _customEcoPolicyRate[account].claimTax;
            } else {
                Constant.EcoPolicyInfo storage userEcoTaxInfo = ecoPolicyInfo[userEcoZone];
                taxPercent = userEcoTaxInfo.claimTax;
            }
        }
        return taxPercent;
    }

    /// @notice 유저의 lock duration 비율에 따른 할인율 반환
    function _getDiscountTaxRate(address account) private view returns (uint256 discountTaxRate) {
        uint256 expiry = locker.expiryOf(account);
        discountTaxRate = 0;
        if (expiry > block.timestamp) {
            discountTaxRate = (expiry.sub(block.timestamp)).mul(100).div(locker.getLockUnitMax());
        }
    }

    /// @notice 전달받은 유저의 ecoZone에 따른 pptTax 반환
    function _getPptTaxRate(Constant.EcoZone ecoZone) private view returns (uint256 pptTaxRate, uint256 gapPercent) {
        gapPercent = calculatePptPriceGap();
        uint256 pptTaxIndex = 0;
        if (gapPercent < pptPhaseInfo.phase1) {
            pptTaxIndex = 0;
        } else if (gapPercent < pptPhaseInfo.phase2) {
            pptTaxIndex = 1;
        } else if (gapPercent < pptPhaseInfo.phase3) {
            pptTaxIndex = 2;
        } else {
            pptTaxIndex = 3;
        }

        if (gapPercent > 0) {
            pptTaxRate = ecoPolicyInfo[ecoZone].pptTax[pptTaxIndex];
        } else {
            pptTaxRate = 0;
        }
    }

    /// @notice 현재 ppt reference price와 grv token price의 가격 차이를 반환
    function calculatePptPriceGap() public view returns (uint256 gapPercent) {
        uint256 currentTokenPrice = priceCalculator.priceOf(GRV);
        uint256 referenceTokenPrice = priceProtectionTaxCalculator.referencePrice();
        uint256 gap = currentTokenPrice >= referenceTokenPrice ? 0 : referenceTokenPrice.sub(currentTokenPrice);
        gapPercent = referenceTokenPrice > 0 ? gap.mul(1e2).div(referenceTokenPrice) : 0;
    }
}

