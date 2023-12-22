// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

interface ISupplyContoller {
        
    /* ========== EVENTS ========== */
    event SupplyControlParamsSet(uint256 lossRatio, uint256 cf, uint256 cc, uint256 samplingTime,
        uint256 oldLossRatio, uint256 oldCf, uint256 oldCc, uint256 oldSamplingTime);
    event Burnt(uint256 totalSupply, uint256 panaInPool, uint256 slp, uint256 panaResidue, uint256 tokenResidue);
    event Supplied(uint256 totalSupply, uint256 panaInPool, uint256 slp, uint256 panaSupplied, uint256 panaResidue, uint256 tokenResidue);
    
    function supplyControlEnabled() external view returns (bool);

    function paramsSet() external view returns (bool);

    function setSupplyControlParams(uint256 _lossRatio, uint256 _cf, uint256 _cc, uint256 _samplingTime) external;

    function enableSupplyControl() external;

    function disableSupplyControl() external;

    function compute() external view returns (uint256 _pana, uint256 _slp, bool _burn);

    function burn(uint256 _slp) external;

    function add(uint256 _pana) external;
}
