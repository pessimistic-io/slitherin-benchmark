//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

interface IMerkleDistributor {
    function claimed(uint256, address) external view returns (bool);
    function setMerkleSet(bytes32 _root, uint256 round) external;
    function withdraw(bytes32[] calldata proof, uint256 amount, uint256 round) external;
    function bail() external;
}


