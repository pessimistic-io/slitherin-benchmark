// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IERC4626 } from "./IERC4626.sol";
import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./ERC20_IERC20.sol";

/**
 * @title batching manager bypass contract
 * @notice it acts as circuit breaker to prevent cooldown on batching manager by receiving sGlp and depositing it into vodkaVault
 * @author Vodka
 **/

contract BatchingManagerBypass is Ownable {
    IERC20 internal sGlp;
    IERC4626 internal vodkaVault;

    /// @notice sets the junior vault address, only owner can call this function
    /// @param _vodkaVault address of VodkaVault
    function setvodkaVault(IERC4626 _vodkaVault) external onlyOwner {
        vodkaVault = _vodkaVault;
    }

    /// @notice sets the junior staked glp address, only owner can call this function
    /// @param _sGlp address of StakedGlp
    function setSglp(IERC20 _sGlp) external onlyOwner {
        sGlp = _sGlp;
        sGlp.approve(address(vodkaVault), type(uint256).max);
    }

    /// @notice receives sGlp from batching manager and deposits it into vodkaVault
    /// @param glpAmount amount of staked glp sent by batching manager
    /// @param receiver address of receiver of vodkaVault shares
    function deposit(uint256 glpAmount, address receiver) external returns (uint256) {
        return vodkaVault.deposit(glpAmount, receiver);
    }
}

