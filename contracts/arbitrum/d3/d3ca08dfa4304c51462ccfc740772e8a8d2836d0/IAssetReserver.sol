//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IAssetReserver {
    function setAssetMinter(address _assetMinter) external;

    function setAssetRedeemer(address _assetRedeemer) external;

    function withdrawFromReserver(address sender, uint256 amount) external;
}

