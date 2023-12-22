// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

abstract contract Reflection is ERC20, Ownable {
    event Deposit(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);
    event Withdraw(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);
    event Claim(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);
    event UpdateProvider(address indexed provider, bool set);

    error TooMuchWithdraw(uint256 max, uint256 amount);
    error ClaimNull(address _account);

    struct ReflectionContext {
        uint256 claimedAmount;
        uint256 accAmount;
    }

    uint256 unitAcc;
    uint256 initialProvision;

    mapping (address => ReflectionContext) contexts;
    uint256 internal constant ACC_AMPLIFIER = 10 ** 36;

    mapping (address => bool) providers;

    modifier onlyProvider() {
        require(providers[msg.sender], "Not Provider");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    }

    function deposit(address snder, uint256 _amount) internal virtual {
        // claim provision first
        _claimProvision(snder);

        ReflectionContext storage ctx = contexts[snder];
        uint256 depositedAmount = balanceOf(snder) + _amount;
        ctx.accAmount = depositedAmount * unitAcc / ACC_AMPLIFIER;

        _mint(snder, _amount);

        emit Deposit(snder, _amount, block.timestamp);
    }

    function withdraw(address snder, uint256 _amount) internal virtual {
        // claim first
        _claimProvision(snder);

        ReflectionContext storage ctx = contexts[snder];
        uint256 depositedAmount = balanceOf(snder);
        if (_amount > depositedAmount) {
            revert TooMuchWithdraw(depositedAmount, _amount);
        }

        depositedAmount -= _amount;
        ctx.accAmount = depositedAmount * unitAcc / ACC_AMPLIFIER;

        _burn(snder, _amount);

        emit Withdraw(snder, _amount, block.timestamp);
    }

    function provide(uint256 _amount) internal virtual {
        uint256 total = totalSupply();
        if (total != 0) {
            if (initialProvision > 0) {
                _amount += initialProvision;
                initialProvision = 0;
            }

            unitAcc += ACC_AMPLIFIER * _amount / total;
        } else {
            initialProvision += _amount;
        }
    }

    function _claimProvision(address user) internal virtual returns (uint256) {
        ReflectionContext storage ctx = contexts[user];

        uint256 _amount = getPendingReward(user);
        if(_amount > 0) {
            ctx.accAmount += _amount;
            ctx.claimedAmount += _amount;
            emit Claim(user, _amount, block.timestamp);
        }

        return _amount;
    }

    function updateProvider(address provider, bool set) external onlyOwner {
        providers[provider] = set;
        emit UpdateProvider(provider, set);
    }

    function getPendingReward(address _account) public view returns (uint256) {
        ReflectionContext storage ctx = contexts[_account];
        uint256 totalReward = balanceOf(_account) * unitAcc / ACC_AMPLIFIER;
        return totalReward > ctx.accAmount? totalReward - ctx.accAmount: 0;
    }

    function getEarningsClaimedByAccount(address _account) external view returns (uint256) {
        return contexts[_account].claimedAmount;
    }

    function getDepositedAmount(address _account) public view returns (uint256) {
        return balanceOf(_account);
    }
}

