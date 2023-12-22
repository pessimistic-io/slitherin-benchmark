// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IHandle.sol";
import "./IHandleComponent.sol";

abstract contract HandlePausable is IHandleComponent {
    function handleAddress() public view virtual override returns (address);

    modifier notPaused() {
        require(!IHandle(handleAddress()).isPaused(), "Paused");
        _;
    }
}

