// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import {OptionLib} from "./OptionLib.sol";

interface ITreasury {
    function payBlxTo(address _to, uint256 _amount) external;
    function takeBlxFrom(address _from, uint256 _amount) external;
    function payTokensTo(address _to, uint256 _amount) external;
    function takeTokensFrom(address _from, uint256 _amount) external;

    function withdrawBlx(
        address user,
        uint256 withdrawAmount,
        uint256 burnAmount
    ) external;

    struct AsymmetryInfo {
        uint256 callCollateral;
        uint256 putCollateral;
    }

    function lockBetCollateral(
        uint256 amount,
        uint256 derivativeId,
        uint256 productType,
        uint256 optionType
    ) external;

    function unlockBetCollateral(
        uint256 amount,
        uint256 derivativeId,
        uint256 productType,
        uint256 optionType
    ) external;

    function totalCollateral(
        uint256 product,
        uint256 derivativeId
    ) external view returns(uint256);

    function getCollateralByOptionType(
        uint256 product,
        uint256 derivativeId,
        uint256 optionType
    ) external returns(uint256);

    function get_r1(
        uint256 product,
        uint256 derivativeId,
        uint256 optionType
    ) external view returns (int128 r1);

    function get_r2(
        uint256 product,
        uint256 derivativeId
    ) external view returns(int128 r2);

    function adjCoeff(
        uint256 product,
        uint256 derivativeId,
        uint256 optionType
    ) external view returns(int128 coef);

    function registerRewardPaid(
        uint amount
    ) external;

    function burnBlxFee(
        uint amount
    ) external;

    function registerBalanceChange(
        address token,
        uint investment,
        uint payout,
        OptionLib.ProductKind product
    ) external;


    function distributeGainLoss() external;

    function notifyPlatformReward(address token, uint reward) external;

    function notifyBlxStakingReward(uint reward) external;

    function blxStakingReward() external returns (uint);
    
    function platformIncome() external returns (uint);

    function distributePlatformIncome() external;

    function totalBeneficiaryIncome() external returns (uint);
}

