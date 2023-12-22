// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OnlyGovernance.sol";

abstract contract OnlyBridge is OnlyGovernance {

    address private bridge;

    function getBridge() public view returns(address){
        return bridge;
    }
    /**
     * @notice Used to set the bridge contract that determines the position
     * ranges and calls rebalance(). Must be called after this vault is
     * deployed.
     */
    function setBridge(address _bridge) external onlyGovernance {
        bridge = _bridge;
    }

    modifier onlyBridge {
        require(msg.sender == bridge, "bridge");
        _;
    }
}
