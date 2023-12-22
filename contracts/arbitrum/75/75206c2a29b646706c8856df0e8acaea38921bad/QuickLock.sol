pragma solidity 0.7.6;

// SPDX-License-Identifier: MIT

import "./IChefIncentivesController.sol";
import "./IMultiFeeDistribution.sol";
import "./IERC20.sol";

contract QuickLock {
    IChefIncentivesController public chef;
    IMultiFeeDistribution public mfd;
    IERC20 public rdntToken;
    address[] public allTokens;

    constructor(
        IChefIncentivesController _chef,
        IMultiFeeDistribution _mfd,
        IERC20 _rdntToken,
        address[] memory _allTokens
    ) {
        chef = _chef;
        mfd = _mfd;
        rdntToken = _rdntToken;

        for (uint256 i = 0; i < _allTokens.length; i += 1) {
            allTokens.push(_allTokens[i]);
        }
    }

    function fromRewards() external {
        uint256 startBalance = rdntToken.balanceOf(msg.sender);
        chef.claim(msg.sender, allTokens);
        mfd.exit(false, msg.sender);
        
        uint256 toTransfer = rdntToken.balanceOf(msg.sender) - startBalance;
        rdntToken.transferFrom(msg.sender, address(this), toTransfer);
        rdntToken.approve(address(mfd), toTransfer);
        mfd.stake(toTransfer, true, msg.sender);
    }

    function fromVesting() external {
        uint256 startBalance = rdntToken.balanceOf(msg.sender);

        mfd.exit(false, msg.sender);
        
        uint256 toTransfer = rdntToken.balanceOf(msg.sender) - startBalance;
        rdntToken.transferFrom(msg.sender, address(this), toTransfer);
        rdntToken.approve(address(mfd), toTransfer);
        mfd.stake(toTransfer, true, msg.sender);
    }
}
