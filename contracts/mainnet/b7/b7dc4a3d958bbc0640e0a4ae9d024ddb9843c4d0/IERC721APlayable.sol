//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "./interfaces_IERC721AQueryable.sol";
import "./IGameplayCoordinator.sol";

interface IERC721APlayable is IERC721AQueryable {
    function addTokenToGameplay(uint256 id) external;
    function removeTokenFromGameplay(uint256 id) external;
    function isTokenInPlay(uint256 tokenId) external view returns(bool);
    function setGameplayCoordinator(IGameplayCoordinator c) external;
}

