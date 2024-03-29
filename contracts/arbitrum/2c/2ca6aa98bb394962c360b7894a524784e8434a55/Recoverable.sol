// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./TinyOwnable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract Recoverable is Ownable {
    using SafeERC20 for IERC20;
    address public vault;

    event TokenRecovery(address indexed token, uint256 amount);
    event EthRecovery(uint256 amount);

    function recoverToken(address _token) external virtual onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance != 0, "Cannot recover zero balance");
        IERC20(_token).safeTransfer(address(vault), balance);
        emit TokenRecovery(_token, balance);
    }

    function recoverEth(address payable _to) external virtual onlyOwner {
        uint256 balance = address(vault).balance;
        _to.transfer(balance);
        emit EthRecovery(balance);
    }

    function recoverTokenCustom(address _token, uint256 _amount)
        external
        virtual
        onlyOwner
    {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance != 0, "Cannot recover zero balance");
        IERC20(_token).safeTransfer(address(vault), _amount);
        emit TokenRecovery(_token, balance);
    }

    function setVaultAddress(address _vault) external virtual onlyOwner {
        vault = _vault;
    }

    // recover to deployer if gnosis vault fails
    function recoverTokenToDeployer(address _token) external virtual onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance != 0, "Cannot recover zero balance");
        IERC20(_token).safeTransfer(address(msg.sender), balance);
        emit TokenRecovery(_token, balance);
    }

    function recoverEthToDeployer(address payable _to)
        external
        virtual
        onlyOwner
    {
        uint256 balance = address(msg.sender).balance;
        _to.transfer(balance);
        emit EthRecovery(balance);
    }
}

