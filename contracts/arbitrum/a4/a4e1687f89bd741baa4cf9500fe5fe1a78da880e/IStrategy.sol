// SPDX-License-Identifier: MIT

interface IStrategy {
    function estimatedTotalAssets() external view returns (uint256);

    function withdrawAll() external returns (uint256);

    function balanceOf() external view returns (uint256);

    function deposit() external;

    function withdraw(uint256) external;

    function rescueTokens(address) external view;

    function want() external view returns (address);
}

