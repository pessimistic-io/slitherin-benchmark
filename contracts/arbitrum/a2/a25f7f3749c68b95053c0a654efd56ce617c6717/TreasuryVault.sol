// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TreasuryVault is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Team address.
    address public teamAddress;

    mapping(address => uint256) public lastUnlock;

    event Unlocked(address indexed token, uint256 amount);

    constructor(address _teamAddress) public {
        teamAddress = _teamAddress;
    }

    function unlock(address _token) public onlyOwner {
        require(
            lastUnlock[_token] + 7 days < block.timestamp,
            "TreasuryVault::unlock: can only unlock once a week"
        );
        lastUnlock[_token] = block.timestamp;

        uint256 amount = IERC20(_token).balanceOf(address(this)).div(2);

        require(
            amount > 0,
            "TreasuryVault::unlock: amount must be greater than 0"
        );

        safeTreasuryTransfer(_token, teamAddress, amount);

        emit Unlocked(_token, amount);
    }

    // Safe transfer function, just in case if rounding error causes contract to not have enough tokens.
    function safeTreasuryTransfer(
        address _tokenAddress,
        address _to,
        uint _amount
    ) internal {
        uint contractBalance = IERC20(_tokenAddress).balanceOf(address(this));

        if (_amount > contractBalance) {
            IERC20(_tokenAddress).safeTransfer(_to, contractBalance);
        } else {
            IERC20(_tokenAddress).safeTransfer(_to, _amount);
        }
    }
}

