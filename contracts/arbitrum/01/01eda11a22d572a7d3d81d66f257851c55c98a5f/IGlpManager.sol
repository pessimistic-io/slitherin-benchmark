// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IGlpManager {
    function getPrice(bool _maximise) external view returns (uint256);

    function addLiquidityForAccount(address account, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
}
