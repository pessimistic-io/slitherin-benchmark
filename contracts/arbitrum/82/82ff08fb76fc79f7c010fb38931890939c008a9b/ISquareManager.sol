//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

/**
    Game manager for Squares.
 */
interface ISquareManager {
    function ownerOfSquare(uint256 _tokenId) external view returns(address);

    function balanceOf(address _owner) external view returns(uint256);

    struct BoardLocation {
        uint256 posX_;
        uint256 poxY_;
    }
}


