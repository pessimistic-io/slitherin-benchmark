//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import { EIP712Upgradeable } from "./draft-EIP712Upgradeable.sol";

import "./IConsumableClaimer.sol";
import "./AdminableUpgradeable.sol";
import "./IConsumable.sol";

abstract contract ConsumableClaimerState is Initializable, IConsumableClaimer, EIP712Upgradeable, AdminableUpgradeable {

    event ConsumableClaimed(address claimer, bytes32 nonce);
    event ConsumableUnclaimed(address claimer, bytes32 nonce);

    bytes32 public constant CLAIMINFO_TYPE_HASH =
        keccak256("ClaimInfo(address claimer,uint256 tokenId,uint256 quantity,bytes32 nonce)");

    IConsumable public consumable;

    mapping(address => mapping(bytes32 => bool)) public claimerToNonceToIsClaimed;

    function __ConsumableClaimerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        EIP712Upgradeable.__EIP712_init("ConsumableClaimer", "1.0.0");
    }
}
