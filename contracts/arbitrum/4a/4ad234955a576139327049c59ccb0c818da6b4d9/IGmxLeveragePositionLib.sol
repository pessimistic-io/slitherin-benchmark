// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IGmxLeveragePositionLib {
    function getOpenPositionsCount() external view returns (uint256);

    function getDebtAssets()
        external
        returns (address[] memory, uint256[] memory);

    function getManagedAssets()
        external
        returns (address[] memory, uint256[] memory);

    function init(bytes memory) external;

    function receiveCallFromVault(bytes memory) external;

    function WETH_TOKEN() external returns (address);
}

