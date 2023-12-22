// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface ILiquidator {
    event Redeem(
        address from,
        address token,
        uint256 tokenAmount,
        uint256[] collateralAmounts,
        address[] collateralTypes
    );

    event Liquidate(
        address from,
        address token,
        uint256 tokenAmount,
        uint256[] collateralAmounts,
        address[] collateralTypes
    );

    function setCrScalar(uint256 value) external;

    function setKeeperPoolThreshold(uint256 amount) external;

    function setRedemptionFeeRatio(uint256 ratio) external;

    function setProtocolRedemptionFeeRatio(uint256 ratio) external;

    function buyCollateral(
        uint256 amount,
        address token,
        address from,
        uint256 deadline,
        address referral
    )
        external
        returns (
            uint256[] memory collateralAmounts,
            address[] memory collateralTypes,
            uint256 etherAmount
        );

    function buyCollateralFromManyVaults(
        uint256 amount,
        address token,
        address[] memory from,
        uint256 deadline,
        address referral
    )
        external
        returns (
            uint256[] memory collateralAmounts,
            address[] memory collateralTypes,
            uint256 etherAmount
        );

    function getLiquidationRatio(address account, address fxToken)
        external
        view
        returns (uint256);

    function liquidate(address account, address fxToken)
        external
        returns (
            uint256 fxAmount,
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        );

    function tokensRequiredForCrIncrease(
        uint256 crTarget,
        uint256 debt,
        uint256 collateral,
        uint256 returnRatio
    ) external pure returns (uint256 amount);

    function getAllowedBuyCollateralFromTokenAmount(address token, address from)
        external
        view
        returns (uint256 allowedAmount, bool isLiquidation);

    function crScalar() external view returns (uint256);

    function keeperPoolThreshold() external view returns (uint256);

    function redemptionFeeRatio() external view returns (uint256);

    function protocolRedemptionFeeRatio() external view returns (uint256);
}

