//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

interface IGohmSSOVV2 {
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
        returns (uint256[1] memory);

    function getEpochStrikeTokens(uint256 epoch)
        external
        view
        returns (address[] memory);

    function getUserEpochDeposits(uint256 epoch, address user)
        external
        view
        returns (uint256[] memory);

    function getEpochStrikes(uint256 epoch)
        external
        view
        returns (uint256[] memory);

    function addToContractWhitelist(address _contract) external returns (bool);

    function bootstrap() external returns (bool);

    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external pure returns (uint256);

    function settlementPrices(uint256 epoch) external view returns (uint256);

    function epochStrikes(uint256 epoch, uint256 index)
        external
        view
        returns (uint256);
}

