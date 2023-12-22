// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {UUPSUpgradeable} from "./utils_UUPSUpgradeable.sol";
import {SafeOwnableUpgradeable} from "./utils_SafeOwnableUpgradeable.sol";
import {IRegistry} from "./IRegistry.sol";
import {DegenShovel} from "./DegenShovel.sol";
import {RBT} from "./RBT.sol";
import {RebornPortal} from "./RebornPortal.sol";
import {PiggyBank} from "./PiggyBank.sol";
import {CommonError} from "./CommonError.sol";

contract Registry is IRegistry, UUPSUpgradeable, SafeOwnableUpgradeable {
    event DegenSet(address degen);
    event PortalSet(address portal);
    event ShovelSet(address shovel);
    event PiggyBankSet(address piggyBank);

    mapping(address => bool) private _signers;
    RBT private _degen;
    RebornPortal private _portal;
    DegenShovel private _shovel;
    PiggyBank private _piggyBank;

    uint256[45] private __gap;

    function initialize(address owner_) public initializer {
        if (owner_ == address(0)) {
            revert CommonError.ZeroAddressSet();
        }
        __Ownable_init_unchained(owner_);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev update signers
     * @param toAdd list of to be added signer
     * @param toRemove list of to be removed signer
     */
    function updateSigners(
        address[] calldata toAdd,
        address[] calldata toRemove
    ) public onlyOwner {
        for (uint256 i = 0; i < toAdd.length; i++) {
            _signers[toAdd[i]] = true;
            emit SignerUpdate(toAdd[i], true);
        }
        for (uint256 i = 0; i < toRemove.length; i++) {
            delete _signers[toRemove[i]];
            emit SignerUpdate(toRemove[i], false);
        }
    }

    function setDegen(RBT addr) public onlyOwner {
        _degen = addr;
        emit DegenSet(address(addr));
    }

    function setPortal(RebornPortal addr) public onlyOwner {
        _portal = addr;
        emit PortalSet(address(addr));
    }

    function setShovel(DegenShovel addr) public onlyOwner {
        _shovel = addr;
        emit ShovelSet(address(addr));
    }

    function setPiggyBank(PiggyBank addr) public onlyOwner {
        _piggyBank = addr;
        emit PiggyBankSet(address(addr));
    }

    function checkIsSigner(address addr) public view returns (bool) {
        return _signers[addr];
    }

    function getDegen() public view returns (RBT) {
        return _degen;
    }

    function getPortal() public view returns (RebornPortal) {
        return _portal;
    }

    function getShovel() public view returns (DegenShovel) {
        return _shovel;
    }

    function getPiggyBank() public view returns (PiggyBank) {
        return _piggyBank;
    }
}

