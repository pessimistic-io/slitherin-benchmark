//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC721EnumerableUpgradeable.sol";

interface IBattlefly is IERC721EnumerableUpgradeable {
    function mintBattlefly(address receiver, uint256 battleflyType) external returns (uint256);

    function mintBattleflies(
        address receiver,
        uint256 _battleflyType,
        uint256 amount
    ) external returns (uint256[] memory);

    function getBattleflyType(uint256) external view returns (uint256);
}

