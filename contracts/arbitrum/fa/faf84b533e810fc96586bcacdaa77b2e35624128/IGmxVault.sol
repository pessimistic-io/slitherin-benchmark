// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";

interface IGmxVault {
    event BuyingEvent(IERC20 token, uint256 amount, uint256 glpAmountReceived);
    event SellingEvent(address receiver, uint256 glpAmount, IERC20 tokenOut);

    function buyGLP(bytes memory _data)
        external
        returns (uint256 glpBoughtAmount);

    function sellGLP(bytes memory _data) external returns (uint256 amountPayed);

    function claimRewards(bytes memory _data) external returns (bool);

    function getTvl() external view returns (uint256);

    function getWeights(IERC20[] calldata _assets)
        external
        view
        returns (uint256[] memory);
}

