// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TreasuryRouter is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Dev address.
    address public devAddress;

    // Vault address.
    address public vaultAddress;

    mapping(address => uint256) public lastDistribution;

    event Paid(address indexed token, uint256 amount, address twitterAddress);

    constructor(address _devAddress, address _vaultAddress) public {
        devAddress = _devAddress;
        vaultAddress = _vaultAddress;

    }

    function distribute(
        address _token,
        address _twitterAddress
    ) public onlyOwner {


        if (lastDistribution[_token] != 0) {
            require(
                lastDistribution[_token] + 7 days < block.timestamp,
                "TreasuryRouter::distribute: can only distribute once a week"
            );
        }
        lastDistribution[_token] = block.timestamp;

        uint256 amount = IERC20(_token).balanceOf(address(this));

        require(
            amount > 0,
            "TreasuryRouter::distribute: amount must be greater than 0"
        );

        uint256 vaultAmount = amount.mul(70).div(100);
        uint256 devAmount = amount.mul(25).div(100);
        uint256 twitterAmount = amount.mul(5).div(100);

        safeTreasuryTransfer(_token, devAddress, devAmount);
        safeTreasuryTransfer(_token, vaultAddress, vaultAmount);
        safeTreasuryTransfer(_token, _twitterAddress, twitterAmount);

        emit Paid(_token, amount, _twitterAddress);
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

