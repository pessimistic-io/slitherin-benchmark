// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Math.sol";
import "./ITaskTreasuryUpgradeable.sol";

contract FeeManager is Ownable() {
    //
    address public immutable nftPerpResolver;
    ITaskTreasuryUpgradable public immutable taskTreasury;

    constructor(address _resolver, address _taskTreasury){
        nftPerpResolver = _resolver;
        taskTreasury = ITaskTreasuryUpgradable(_taskTreasury);
    }

    //Fund Gelato Tasks on NFT-perp-resolver
    function fundGelatoTasksETH(uint256 _amount) external onlyOwner(){
        uint256 amount = Math.min(address(this).balance, _amount);
        taskTreasury.depositFunds{value: amount}(
            nftPerpResolver, 
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 
            0
        );
    }
    receive() external payable {}
}
