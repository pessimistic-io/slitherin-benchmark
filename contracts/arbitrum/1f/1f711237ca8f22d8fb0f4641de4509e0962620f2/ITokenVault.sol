//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

import "./TokenVault_Types.sol";

interface ITokenVault is IERC721Enumerable {
  function withdrawToken (uint playerId, address to) external;
  function depositToken (UserToken memory token, address from) external;
  function resolveToken (uint) external view returns (UserToken memory);
  function resolvePlayerId (UserToken memory token) external view returns (uint);
  function playableToken (uint playerId) external view returns (bool);
  function depositableToken (UserToken memory) external view returns (bool);
}
