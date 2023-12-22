// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.17;

import "./IFactorGaugeControllerMainchain.sol";
import "./FactorGaugeControllerBase.sol";

contract FactorGaugeControllerMainchain is FactorGaugeControllerBase, IFactorGaugeControllerMainchain {

    error GCNotFactorScale(address caller);

    address public factorScale;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _esFctr, 
        address _factorScale
    ) public initializer {
        __Ownable_init(msg.sender);
        __FactorGaugeControllerBase_init(_esFctr);
        factorScale = _factorScale;
    }

    function updateVotingResults(
        uint128 wTime,
        address[] memory vaults,
        uint256[] memory fctrAmounts
    ) external {
        if (msg.sender != factorScale) revert GCNotFactorScale(msg.sender);

        _receiveVotingResults(wTime, vaults, fctrAmounts);
    }
}

