// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "./Ownable.sol";
import {IEntryPoint} from "./IEntryPoint.sol";

/**
 * @title Stakeable Entity
 * @author Fil Makarov - <filipp.makarov@biconomy.io>
 */
contract Stakeable is Ownable {
    constructor(address _newOwner) {
        _transferOwnership(_newOwner);
    }

    function addStake(
        address epAddress,
        uint32 unstakeDelaySec
    ) external payable onlyOwner {
        require(epAddress != address(0), "Invalid EP address");
        IEntryPoint(epAddress).addStake{value: msg.value}(unstakeDelaySec);
    }

    function unlockStake(address epAddress) external onlyOwner {
        require(epAddress != address(0), "Invalid EP address");
        IEntryPoint(epAddress).unlockStake();
    }

    function withdrawStake(
        address epAddress,
        address payable withdrawAddress
    ) external onlyOwner {
        require(epAddress != address(0), "Invalid EP address");
        IEntryPoint(epAddress).withdrawStake(withdrawAddress);
    }
}

