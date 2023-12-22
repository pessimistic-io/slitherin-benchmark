// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20.sol";

import "./SingleStakingManager.sol";

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw an error.
 * Based off of https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol.
 */
library SafeMath {
    /*
     * Internal functions
     */

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract SingleStaking {
    event Enter(address user, uint256 dicedAmount, uint256 shares);
    event Leave(address user, uint256 dicedAmount, uint256 shares);

    using SafeMath for uint256;
    IERC20 public immutable diced;
    SingleStakingManager public immutable stakingManager;
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    constructor(IERC20 _diced) {
        diced = _diced;
        stakingManager = SingleStakingManager(msg.sender);
    }

    // Locks Diced, update the user's shares (non-transferable)
    function enter(uint256 _amount) public returns (uint256 sharesToMint) {
        // Before doing anything, get the unclaimed rewards first
        stakingManager.distributeRewards();
        // Gets the amount of Diced locked in the contract
        uint256 totalDiced = diced.balanceOf(address(this));
        if (totalSupply == 0 || totalDiced == 0) {
            // If no shares exists, mint it 1:1 to the amount put in
            sharesToMint = _amount;
        } else {
            // Calculate and mint the amount of shares the Diced is worth. The ratio will change overtime, as shares is burned/minted and Diced distributed to this contract
            sharesToMint = _amount.mul(totalSupply).div(totalDiced);
        }
        _mint(msg.sender, sharesToMint);
        // Lock the Diced in the contract
        diced.transferFrom(msg.sender, address(this), _amount);
        emit Enter(msg.sender, _amount, sharesToMint);
    }

    // Unlocks the staked + gained Diced and burns shares
    function leave(uint256 _share) public returns (uint256 rewards) {
        // Before doing anything, get the unclaimed rewards first
        stakingManager.distributeRewards();
        // Calculates the amount of Diced the shares is worth
        rewards = _share.mul(diced.balanceOf(address(this))).div(totalSupply);
        _burn(msg.sender, _share);
        diced.transfer(msg.sender, rewards);
        emit Leave(msg.sender, rewards, _share);
    }

    function _mint(address user, uint256 amount) internal {
        balances[user] = balances[user].add(amount);
        totalSupply = totalSupply.add(amount);
    }

    function _burn(address user, uint256 amount) internal {
        balances[user] = balances[user].sub(amount);
        totalSupply = totalSupply.sub(amount);
    }
}

