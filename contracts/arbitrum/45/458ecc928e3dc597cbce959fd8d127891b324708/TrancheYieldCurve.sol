//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./CoreRef.sol";

contract TrancheYieldCurve is CoreRef {
    using SafeMath for uint256;

    uint256 private PERCENTAGE_SCALE = 1e18;
    uint256 public year = 31536000;
    uint256 public fixedAPR = 100e14;

    event YieldDistribution(
        uint256 fixedSeniorYield,
        uint256 juniorYield,
        uint256[] seniorFarmYield,
        uint256[] juniorFarmYield
    );

    struct YieldDistrib {
        uint256 fixedSeniorYield;
        uint256 juniorYield;
        uint256[] seniorFarmYield;
        uint256[] juniorFarmYield;
    }

    constructor(address _core, uint256 _fixedAPR) CoreRef(_core) {
        fixedAPR = _fixedAPR;
    }

    function setSeniorAPR(uint256 _apr) public onlyTimelock {
        require(_apr > 0, "Tranche Yield Curve: APR should be a positive number");
        fixedAPR = _apr;
    }

    function getYieldDistribution(
        uint256 _seniorProportion,
        uint256 _totalPrincipal,
        uint256 _restCapital,
        uint256 _cycleDuration,
        uint256[] memory _farmedTokensAmts
    ) external returns (YieldDistrib memory) {
        uint256 totalYield;
        YieldDistrib memory distrib;
        distrib.seniorFarmYield = new uint256[](_farmedTokensAmts.length);
        distrib.juniorFarmYield = new uint256[](_farmedTokensAmts.length);

        // calculate how much senior tranche should get
        // fixedAPR * senior tranche thickness * totalPrincipal

        uint256 expectedCycleAPR = fixedAPR.mul(_cycleDuration).div(year);
        distrib.fixedSeniorYield = expectedCycleAPR.mul(_totalPrincipal).mul(_seniorProportion).div(
            PERCENTAGE_SCALE ** 2
        );
        if (_restCapital >= _totalPrincipal) {
            totalYield = _restCapital.sub(_totalPrincipal);
        } else {
            totalYield = 0;
        }
        if (distrib.fixedSeniorYield >= totalYield) {
            distrib.juniorYield = 0;
        } else {
            distrib.juniorYield = totalYield.sub(distrib.fixedSeniorYield);
        }

        // calculate farmed tokens distribution
        // formula: (maxFarmAPR or seniorTrancheThickness) * farmTokenAPR * seniorTrancheThickeness * totalPrincipal
        uint256 maxFarmAPR = PERCENTAGE_SCALE.div(2); // 50 % maxFarmShare
        if (_seniorProportion >= maxFarmAPR) {
            for (uint256 i = 0; i < _farmedTokensAmts.length; i++) {
                distrib.seniorFarmYield[i] = (_farmedTokensAmts[i].mul(maxFarmAPR).div(PERCENTAGE_SCALE));
            }
        } else {
            for (uint256 i = 0; i < _farmedTokensAmts.length; i++) {
                distrib.seniorFarmYield[i] = _farmedTokensAmts[i].mul(_seniorProportion).div(PERCENTAGE_SCALE);
            }
        }

        for (uint256 i = 0; i < _farmedTokensAmts.length; i++) {
            if (_farmedTokensAmts[i] > distrib.seniorFarmYield[i]) {
                distrib.juniorFarmYield[i] = _farmedTokensAmts[i].sub(distrib.seniorFarmYield[i]);
            } else {
                distrib.juniorFarmYield[i] = 0;
            }
        }

        emit YieldDistribution(
            distrib.fixedSeniorYield,
            distrib.juniorYield,
            distrib.seniorFarmYield,
            distrib.juniorFarmYield
        );
        return distrib;
    }
}

