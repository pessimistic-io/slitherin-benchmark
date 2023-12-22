// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./REUSDExit.sol";

contract TestREUSDExit is REUSDExit
{
    uint256 nextContractVersion;
    function contractVersion() public override(UUPSUpgradeableVersion, IUUPSUpgradeableVersion) view returns (uint256) { return nextContractVersion; }
    function setContractVersion(uint256 version) public { nextContractVersion = version; }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IREUSD _REUSD, IREStablecoins _stablecoins)
        REUSDExit(_REUSD, _stablecoins)
    {        
    }
}
