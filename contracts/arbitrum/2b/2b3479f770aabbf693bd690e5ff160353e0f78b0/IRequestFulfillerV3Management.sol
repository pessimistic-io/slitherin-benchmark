// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IPlatformPositionHandler.sol";
import "./IVolatilityTokenActionHandler.sol";
import "./IVolatilityTokenActionHandler.sol";
import "./IHedgedThetaVaultActionHandler.sol";
import "./IMegaThetaVaultActionHandler.sol";

interface IRequestFulfillerV3Management {

    event MinPlatformAmountsSet(uint168 newMinOpenAmount, uint168 newMinCloseAmount);
    event MinVolTokenAmountsSet(uint168 newMinMintAmount, uint168 newMinBurnAmount);
    event MinThetaVaultAmountsSet(uint168 newMinDepositAmount, uint168 newMinWithdrawAmount);
    event CVIPlatformSet(address newCVIPlatform);
    event UCVIPlatformSet(address newUCVIPlatform);
    event ReversePlatformSet(address newReversePlatform);
    event CVIVolTokenSet(address newCVIVolToken);
    event UCVIVolTokenSet(address newUCVIVolToken);
    event HedgedVaultSet(address newHedgedVault);
    event MegaVaultSet(address newMegaVault);
    event MinCVIDiffAllowedPercentageSet(uint32 newWithdarwFeePercentage);

    function setMinPlatformAmounts(uint168 newMinOpenAmount, uint168 newMinCloseAmount) external;
    function setMinVolTokenAmounts(uint168 newMinMintAmount, uint168 newMinBurnAmount) external;
    function setMinThetaVaultAmounts(uint168 newMinDepositAmount, uint168 newMinWithdrawAmount) external;
    function setCVIPlatform(IPlatformPositionHandler cviPlatform) external;
    function setUCVIPlatform(IPlatformPositionHandler ucviPlatform) external;
    function setReversePlatform(IPlatformPositionHandler reversePlatform) external;
    function setCVIVolToken(IVolatilityTokenActionHandler cviVolToken) external;
    function setUCVIVolToken(IVolatilityTokenActionHandler ucviVolToken) external;
    function setHedgedVault(IHedgedThetaVaultActionHandler newHedgedVault) external;
    function setMegaVault(IMegaThetaVaultActionHandler newMegaVault) external;
    function setMinCVIDiffAllowedPercentage(uint32 newMinCVIDiffAllowedPercentage) external;
}

