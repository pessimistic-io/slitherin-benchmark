//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISSOV {
    function epochStrikeTokens(uint256 epoch, uint256 strike)
        external
        view
        returns (address);

    function purchase(uint256 strikeIndex, uint256 amount)
        external
        returns (uint256, uint256);

    function exercise(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256, uint256);

    function getAddress(bytes32 name) external view returns (address);
}

