//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ICorruption.sol";
import "./AdminableUpgradeable.sol";

abstract contract CorruptionState is Initializable, ICorruption, ERC20Upgradeable, AdminableUpgradeable {

    event CorruptionStreamModified(address _account, uint128 _ratePerSecond, uint256 _generatedCorruptionCap);
    event CorruptionStreamBoostModified(address _account, uint32 _boost);

    mapping(address => CorruptionStreamInfo) public addressToStreamInfo;

    function __CorruptionState_init() internal initializer {
        ERC20Upgradeable.__ERC20_init("Corruption", "$COR");
        AdminableUpgradeable.__Adminable_init();
    }
}

struct CorruptionStreamInfo {
    // Slot 1
    // The time the corruption token was last minted for this corruption stream.
    uint128 timeLastMinted;
    // A boost out of 100,000 that acts as a multiplier on the ratePerSecond.
    uint32 boost;
    uint96 emptySpace1;

    // Slot 2
    // The rate per second that corruption on this address accumulates.
    uint128 ratePerSecond;
    uint128 emptySpace2;

    // Slot 3
    // The amount of corruption that will be generated up to. If the corruption balance
    // is greater than this, no corruption will be minted.
    uint256 generatedCorruptionCap;
}

