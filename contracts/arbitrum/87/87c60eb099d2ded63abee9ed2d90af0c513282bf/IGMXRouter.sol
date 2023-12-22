// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IGMXRouter {

    function approvePlugin(address _plugin) external;

    function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external;

    // require(_path[_path.length - 1] == weth
    function swapTokensToETH(address[] memory _path, uint256 _amountIn, uint256 _minOut, address payable _receiver) external;
}
