// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./IStrategyV7.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

// Simulate a harvest while recieving a call reward. Return callReward amount and whether or not it was a success. 
contract BeefyHarvestLens {
    using SafeERC20 for IERC20;

    // What is the call reward token? 
    IERC20 public native; 
    bool private _init;

    constructor(){}

    function init(IERC20 _native) external {
        require (!_init);
        native = _native;
        _init = true;
    }

    // Simulate harvest calling callStatic for return results. Can also just call harvest and get reward.
    function harvest(IStrategyV7 _strategy) external returns (uint256 callReward, bool success) {
        try _strategy.harvest(address(this)) {
            callReward = IERC20(native).balanceOf(address(this));
            success = true;
            if (callReward > 0) native.safeTransfer(msg.sender, callReward);
        } catch {
            // explicitly call it out for readability;
            callReward = 0; 
            success = false;
        }
    }
}
