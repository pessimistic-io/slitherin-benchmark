// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;
/**
 * @title Art for Liquidity-Book Multi-Token for representing Fungible Liquidity Positions artistically.
 * @author Sam (543#3017, ELITE & Guru Network)
 * @notice Required interface of LBFactory contract
 */
interface IArt {

    function getUri(address lbPair, uint256 id) external view returns (string memory);

}

