// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./hPSM.sol";

abstract contract HlpRouterUtils is Ownable {
    address public hlpRouter;

    event ChangeHlpRouter(address newHlpRouter);

    constructor(address _hlpRouter) {
        hlpRouter = _hlpRouter;

        emit ChangeHlpRouter(_hlpRouter);
    }

    /** @notice Sets the router address */
    function setHlpRouter(address _hlpRouter) external onlyOwner {
        require(hlpRouter != _hlpRouter, "Address already set");
        hlpRouter = _hlpRouter;
        emit ChangeHlpRouter(hlpRouter);
    }
}

