//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./IQuadPassport.sol";
import "./IQuadGovernance.sol";

import "./QuadReaderStore.sol";

contract QuadReaderStoreV2 is QuadReaderStore{
    // SignatureHash => bool
    mapping(bytes32 => bool) internal _usedFlashSigHashes;
}

