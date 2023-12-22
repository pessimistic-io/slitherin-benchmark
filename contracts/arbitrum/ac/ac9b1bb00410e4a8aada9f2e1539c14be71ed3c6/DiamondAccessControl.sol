// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC173 } from "./IERC173.sol";
import { DiamondOwnable } from "./DiamondOwnable.sol";
import { WithStorage } from "./LibStorage.sol";

contract DiamondAccessControl is WithStorage, DiamondOwnable {
    function setGuardian(address account, bool state) external onlyOwner {
        gs().guardian[account] = state;
    }

    function isGuardian(address account) external view returns (bool) {
        return gs().guardian[account];
    }

    function setBattleflyBot(address account) external onlyOwner {
        gs().battleflyBot = account;
    }

    function isBattleflyBot(address account) external view returns (bool) {
        return (gs().battleflyBot == account);
    }

    function setSigner(address account, bool state) external onlyOwner {
        gs().signer[account] = state;
    }

    function isSigner(address account) external view returns (bool) {
        return gs().signer[account];
    }

    function setEmissionDepositor(address account, bool state) external onlyOwner {
        gs().emissionDepositor[account] = state;
    }

    function isEmissionDepositor(address account) external view returns (bool) {
        return gs().emissionDepositor[account];
    }

    function setBackendExecutor(address account, bool state) external onlyOwner {
        gs().backendExecutor[account] = state;
    }

    function isBackendExecutor(address account) external view returns (bool) {
        return gs().backendExecutor[account];
    }
}

