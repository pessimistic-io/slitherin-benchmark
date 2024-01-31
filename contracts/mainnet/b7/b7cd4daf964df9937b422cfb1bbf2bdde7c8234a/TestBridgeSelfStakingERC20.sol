// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.17;

import "./BridgeSelfStakingERC20.sol";
import "./UpgradeableBase.sol";

contract TestBridgeSelfStakingERC20 is BridgeSelfStakingERC20, UpgradeableBase(1)
{
    uint256 nextContractVersion;
    function contractVersion() public override(UUPSUpgradeableVersion, IUUPSUpgradeableVersion) view returns (uint256) { return nextContractVersion; }
    function setContractVersion(uint256 version) public { nextContractVersion = version; }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20 _rewardToken) 
        SelfStakingERC20(_rewardToken, "Test Token", "TST", 18)
    {        
    }

    function mint(uint256 amount) public 
    {
        mintCore(msg.sender, amount);
    }

    function checkUpgradeBase(address newImplementation) internal override view {}
    function getMinterOwner() internal override view returns (address) { return owner(); }
    function getSelfStakingERC20Owner() internal override view returns (address) { return owner(); }
}
