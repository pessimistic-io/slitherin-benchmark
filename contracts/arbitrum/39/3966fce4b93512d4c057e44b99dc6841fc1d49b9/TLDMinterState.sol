//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ITLDMinter.sol";
import "./ITLD.sol";
import "./AdminableUpgradeable.sol";

abstract contract TLDMinterState is
    Initializable,
    ITLDMinter,
    AdminableUpgradeable
{
    event TLDMint(address indexed _owner, uint256 _batchSize);

    ITLD public tld;

    mapping(address => bool) public addressToHasClaimed;

    bytes32 public merkleRoot;

    uint8 public maxBatchSize;

    function __TLDMinterState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        maxBatchSize = 20;
    }
}

