// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "./BaseSupplyController.sol";

contract ProportionalSupplyController is BaseSupplyController {   
    event PCoefficientSet(int256 kp, int256 oldKp);

    // Proportional gain, 4 decimals
    int256 public kp;

    constructor(
        int256 _kp,
        address _PANA,
        address _pair, 
        address _router, 
        address _supplyControlCaller,
        address _authority
    ) BaseSupplyController(_PANA, _pair, _router, _supplyControlCaller, _authority) {
        kp = _kp;
    }

    function setPCoefficient(int256 _kp) external onlyPolicy {
        require(_kp <= 10000, "Proportional coefficient cannot be more than 1");
       
        int256 oldKp = kp;
        kp = _kp;

        emit PCoefficientSet(kp, oldKp);
    }

    function computePana(uint256 _targetSupply, uint256 _panaInPool, uint256 _dt) internal override view returns (int256) {
        return (int256(_targetSupply) - int256(_panaInPool)) * kp / 10**4;
    }
}
