// SPDX-License-Identifier: Unlicense
// Creator: Pixel8 Labs
pragma solidity ^0.8.7;

interface IProvider {
    function stake(address from, uint256 _amountUSDC) external;
    function stakeByAdapter(uint256 _amountUSDC) external;
    function unstake(address from, uint256 _amountMVLP) external returns (uint256);
    function claim(address to) external returns (uint256, uint256, string memory);
    function currentDepositFee() external view returns (uint256);
    function migrate(address provider) external returns (uint256);
    function withdrawERC20(address erc20, address to) external;
    function withdrawETH(address to) external payable;
}
