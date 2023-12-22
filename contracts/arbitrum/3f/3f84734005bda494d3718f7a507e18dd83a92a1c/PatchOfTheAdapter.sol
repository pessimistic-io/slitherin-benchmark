//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IMasterChefV2, UserStruct, IRewarder} from "./IMasterChefV2.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract PatchOfTheAdapter is Ownable, ReentrancyGuard {
    mapping(address => bool) public isVault;

    struct BalancesAndToken {
        uint256 balance;
        address token;
    }

    /// @dev Vault address => LP address and balance
    mapping(address => BalancesAndToken) public vault;

    constructor(address[] memory _vaults, BalancesAndToken[] memory _vaultsInfo) {
        for (uint256 i; i < _vaults.length; i++) {
            isVault[_vaults[i]] = true;
            vault[_vaults[i]] = _vaultsInfo[i];
        }
    }

    function balanceOf(address _user) external view returns (uint256) {
        return vault[_user].balance;
    }

    function stake(uint256 _amount) external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transferFrom(msg.sender, address(this), _amount);

        vault[msg.sender].balance += _amount;
    }

    function unstake(uint256 _amount) external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transfer(msg.sender, _amount);

        vault[msg.sender].balance -= _amount;
    }

    function exit() external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transfer(msg.sender, vault[msg.sender].balance);

        vault[msg.sender].balance = 0;
    }

    function deposit(uint256 pid, uint256 amount, address to) external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transferFrom(msg.sender, address(this), amount);

        vault[msg.sender].balance += amount;
    }

    function withdraw(uint256 pid, uint256 amount, address to) external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transfer(msg.sender, amount);

        vault[msg.sender].balance -= amount;
    }

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external nonReentrant {
        require(isVault[msg.sender], "onlyVault()");

        IERC20(vault[msg.sender].token).transfer(msg.sender, amount);

        vault[msg.sender].balance -= amount;
    }

    function rescue(IERC20 _token, uint256 _amount) external onlyOwner {
        _token.transfer(msg.sender, _amount);
    }

    function updateMapping(address _vault, bool _authorized) external onlyOwner {
        isVault[_vault] = _authorized;
    }

    function updateTokenAndBalance(address _vault, BalancesAndToken memory _structVault) external onlyOwner {
        vault[_vault] = _structVault;
    }

    function rewarder(uint256 _pid) external view returns (IRewarder) {
        require(isVault[msg.sender], "onlyVault()");
    }

    function harvest(uint256 pid, address to) external {
        require(isVault[msg.sender], "onlyVault()");
    }

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256 pending) {
        require(isVault[msg.sender], "onlyVault()");
    }

    function claim() external {
        require(isVault[msg.sender], "onlyVault()");
    }
}

