// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";
import "./IERC20.sol";

contract DestroyedERC20 is UpgradeableBase(0)
{
    uint8 public constant decimals = 0;
    bool public constant isBridgeable = true;
    bool public constant isRERC20 = true;
    bool public constant isREUP = true;
    bool public constant isREUSD = true;
    bool public constant isREYIELD = true;
    bool public constant isSelfStakingERC20 = true;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bytes32 public immutable nameHash;
    address public constant rewardToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor(string memory _name)
    {
        nameHash = keccak256(bytes(_name));
    }
    
    function checkUpgradeBase(address newImplementation) internal override view {}
}
