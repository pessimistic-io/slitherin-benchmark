// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IVerifier2 {
  function verifyProof(
    uint256[2] memory a,
    uint256[2][2] memory b,
    uint256[2] memory c,
    uint256[11] memory input
  ) external view returns (bool);
}

