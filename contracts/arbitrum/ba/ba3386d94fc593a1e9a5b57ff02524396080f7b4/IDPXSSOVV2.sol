//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

interface IDPXSSOVV2 {
    function currentEpoch() external view returns (uint256);

    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (bool);

    function depositMultiple(
        uint256[] calldata strikeIndices,
        uint256[] calldata amounts,
        address user
    ) external returns (bool);

    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256, uint256);

    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch
    ) external returns (uint256 pnl);

    function withdraw(uint256 withdrawEpoch, uint256 strikeIndex)
        external
        returns (uint256[2] memory); // biggest difference

    function getEpochStrikeTokens(uint256 epoch)
        external
        view
        returns (address[] memory);

    function getUserEpochDeposits(uint256 epoch, address user)
        external
        view
        returns (uint256[] memory);
}

