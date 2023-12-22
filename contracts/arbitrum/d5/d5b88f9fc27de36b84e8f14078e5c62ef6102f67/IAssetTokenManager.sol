//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IAssetTokenManager {
    function mint(address token, uint256 amount) external;

    function burn(address token, uint256 amount) external;

    function mintForReserver(address token, uint256 amount) external;

    function burnForReserver(address token, uint256 amount) external;

    function checkAssetReserver(
        address token,
        uint256 amount
    ) external returns (bool);

    function assets(address token) external returns (bool);

    function reservers(address reservers) external returns (bool);

    function assetsReservers(address token) external returns (address);

    function withdrawFromReserver(
        address sender,
        address asset,
        uint256 amount
    ) external;
}

