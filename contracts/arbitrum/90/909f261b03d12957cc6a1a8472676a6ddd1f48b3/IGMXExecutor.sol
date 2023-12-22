// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IGMXExecutor {
    function mint(address _token, uint256 _amountIn) external payable returns (address, uint256);

    function claimRewards() external returns (uint256);

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) external returns (uint256);

    function stakeGlp(address _spender, uint256 _glpAmountIn) external returns (bool);

    function unstakeGlp(address _recipient, uint256 _glpAmountOut) external returns (bool);
}

