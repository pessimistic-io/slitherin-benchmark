// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./Constant.sol";

interface IEcoScore {
    event SetGRVDistributor(address newGRVDistributor);
    event SetPriceProtectionTaxCalculator(address newPriceProtectionTaxCalculator);
    event SetPriceCalculator(address priceCalculator);
    event SetLendPoolLoan(address lendPoolLoan);
    event SetEcoPolicyInfo(
        Constant.EcoZone _zone,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] _pptTax
    );
    event SetAccountCustomEcoPolicy(
        address indexed account,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] _pptTax
    );
    event RemoveAccountCustomEcoPolicy(address indexed account);
    event ExcludeAccount(address indexed account);
    event IncludeAccount(address indexed account);
    event SetEcoZoneStandard(
        uint256 _minExpiryOfGreenZone,
        uint256 _minExpiryOfLightGreenZone,
        uint256 _minDrOfGreenZone,
        uint256 _minDrOfLightGreenZone,
        uint256 _minDrOfYellowZone,
        uint256 _minDrOfOrangeZone
    );
    event SetPPTPhaseInfo(uint256 _phase1, uint256 _phase2, uint256 _phase3, uint256 _phase4);

    function setGRVDistributor(address _grvDistributor) external;

    function setPriceProtectionTaxCalculator(address _priceProtectionTaxCalculator) external;

    function setPriceCalculator(address _priceCalculator) external;

    function setLendPoolLoan(address _lendPoolLoan) external;

    function setEcoPolicyInfo(
        Constant.EcoZone _zone,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] calldata _pptTax
    ) external;

    function setAccountCustomEcoPolicy(
        address account,
        uint256 _boostMultiple,
        uint256 _maxBoostCap,
        uint256 _boostBase,
        uint256 _redeemFee,
        uint256 _claimTax,
        uint256[] calldata _pptTax
    ) external;

    function setEcoZoneStandard(
        uint256 _minExpiryOfGreenZone,
        uint256 _minExpiryOfLightGreenZone,
        uint256 _minDrOfGreenZone,
        uint256 _minDrOfLightGreenZone,
        uint256 _minDrOfYellowZone,
        uint256 _minDrOfOrangeZone
    ) external;

    function setPPTPhaseInfo(uint256 _phase1, uint256 _phase2, uint256 _phase3, uint256 _phase4) external;

    function removeAccountCustomEcoPolicy(address account) external;

    function excludeAccount(address account) external;

    function includeAccount(address account) external;

    function calculateEcoBoostedSupply(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) external view returns (uint256);

    function calculateEcoBoostedBorrow(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore
    ) external view returns (uint256);

    function calculatePreEcoBoostedSupply(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore,
        Constant.EcoZone ecoZone
    ) external view returns (uint256);

    function calculatePreEcoBoostedBorrow(
        address market,
        address user,
        uint256 userScore,
        uint256 totalScore,
        Constant.EcoZone ecoZone
    ) external view returns (uint256);

    function calculateCompoundTaxes(
        address account,
        uint256 value,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view returns (uint256 adjustedValue, uint256 taxAmount);

    function calculateClaimTaxes(
        address account,
        uint256 value
    ) external view returns (uint256 adjustedValue, uint256 taxAmount);

    function getClaimTaxRate(
        address account,
        uint256 value,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view returns (uint256);

    function getDiscountTaxRate(address account) external view returns (uint256);

    function getPptTaxRate(Constant.EcoZone ecoZone) external view returns (uint256 pptTaxRate, uint256 gapPercent);

    function getEcoZone(uint256 ecoDRpercent, uint256 remainExpiry) external view returns (Constant.EcoZone ecoZone);

    function updateUserClaimInfo(address account, uint256 amount) external;

    function updateUserCompoundInfo(address account, uint256 amount) external;

    function updateUserEcoScoreInfo(address account) external;

    function accountEcoScoreInfoOf(address account) external view returns (Constant.EcoScoreInfo memory);

    function ecoPolicyInfoOf(Constant.EcoZone zone) external view returns (Constant.EcoPolicyInfo memory);

    function calculatePreUserEcoScoreInfo(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view returns (Constant.EcoZone ecoZone, uint256 ecoDR, uint256 userScore);
}

