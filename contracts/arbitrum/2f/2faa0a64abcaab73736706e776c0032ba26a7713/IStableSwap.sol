// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;
interface IStableSwap {
   function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
}
