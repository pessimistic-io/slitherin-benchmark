// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

interface INUONController {

    function getMintLimit(uint256 _nuonAmount) external view returns (uint256);

    function addPool(address pool_address) external;

    function getPools() external view returns (address[] memory);

    function addPools(address[] memory poolAddress) external;

    function removePool(address pool_address) external;

    function getNUONSupply() external view returns (uint256);

    function isPool(address pool) external view returns (bool);

    function isMintPaused() external view returns (bool);

    function isRedeemPaused() external view returns (bool);

    function isAllowedToMint(address _minter) external view returns (bool);

    function setFeesParameters(uint256 _mintingFee, uint256 _redeemFee)
        external;

    function setGlobalCollateralRatio(uint256 _globalCollateralRatio) external;

    function getMintingFee(address _CHUB) external view returns (uint256);

    function getRedeemFee(address _CHUB) external view returns (uint256);

    function getGlobalCollateralRatio(address _CHUB) external view returns (uint256);

    function getGlobalCollateralValue() external view returns (uint256);

    function toggleMinting() external;

    function toggleRedeeming() external;

    function getTargetCollateralValue() external view returns (uint256);

    function getMaxCratio(address _CHUB) external view returns (uint256);
}

