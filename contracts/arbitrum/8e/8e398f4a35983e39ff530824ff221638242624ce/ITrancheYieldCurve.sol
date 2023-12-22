//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITrancheYieldCurve {
    struct YieldDistrib {
        uint256 fixedSeniorYield;
        uint256 juniorYield;
        uint256[] seniorFarmYield;
        uint256[] juniorFarmYield;
    }

    function getYieldDistribution(
        uint256 _seniorProportion,
        uint256 _totalPrincipal,
        uint256 _restCapital,
        uint256 _cycleDuration,
        uint256[] memory _farmedTokensAmts
    ) external view returns (YieldDistrib memory);

    function setSeniorAPR(uint256 _apr) external;
}

