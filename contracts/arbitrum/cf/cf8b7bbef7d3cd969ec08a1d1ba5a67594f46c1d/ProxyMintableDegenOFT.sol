// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ProxyOFT} from "./ProxyOFT.sol";
import {IDegen} from "./IDegen.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {Ownable} from "./Ownable.sol";

contract ProxyMintableDegenOFT is ProxyOFT, Ownable2Step {
    constructor(
        address _lzEndpoint,
        address _token,
        address _owner
    ) ProxyOFT(_lzEndpoint, _token) {
        _transferOwnership(_owner);
    }

    /**
     * @dev override and set pattern to Ownable2Step function
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(
        address newOwner
    ) internal virtual override(Ownable2Step, Ownable) {
        Ownable2Step._transferOwnership(newOwner);
    }

    /**
     * @dev override and set pattern to Ownable2Step function
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(
        address newOwner
    ) public virtual override(Ownable2Step, Ownable) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint _amount
    ) internal virtual override returns (uint) {
        IDegen(address(innerToken)).burnFrom(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        IDegen(address(innerToken)).mint(_toAddress, _amount);
        return _amount;
    }
}

