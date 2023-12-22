// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract OnlyGovernance {

    address private governance;
    address private pendingGovernance;

    constructor() {
        governance = msg.sender;
    }

    function getGovernance() public view returns(address){
        return governance;
    }

    function getPendingGovernance() public view returns(address){
        return pendingGovernance;
    }

    /**
     * @notice Governance address is not updated until the new governance
     * address has called `acceptGovernance()` to accept this responsibility.
     */
    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    /**
     * @notice `setGovernance()` should be called by the existing governance
     * address prior to calling this function.
     */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "pendingGovernance");
        governance = msg.sender;
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "governance");
        _;
    }
}

