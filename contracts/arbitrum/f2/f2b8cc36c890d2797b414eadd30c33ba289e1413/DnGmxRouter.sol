// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IDnGmxJuniorVault} from "./IDnGmxJuniorVault.sol";
import {IDnGmxBatchingManager} from "./IDnGmxBatchingManager.sol";

import {IDnGmxRouter} from "./IDnGmxRouter.sol";
import {IDnGmxJIT} from "./IDnGmxJIT.sol";

contract DnGmxRouter is IDnGmxRouter, OwnableUpgradeable {
    IDnGmxJuniorVault public dnGmxJuniorVault;
    IDnGmxBatchingManager public dnGmxBatchingManager;
    IDnGmxJIT public dnGmxJIT;
    IERC20 public sGLP;

    function initialize(
        IDnGmxJuniorVault _dnGmxJuniorVault,
        IDnGmxBatchingManager _dnGmxBatchingManager,
        IDnGmxJIT _dnGmxJIT,
        IERC20 _sGLP
    ) external initializer {
        __Ownable_init();
        __DnGmxRouter_init(
            _dnGmxJuniorVault,
            _dnGmxBatchingManager,
            _dnGmxJIT,
            _sGLP
        );
    }

    function __DnGmxRouter_init(
        IDnGmxJuniorVault _dnGmxJuniorVault,
        IDnGmxBatchingManager _dnGmxBatchingManager,
        IDnGmxJIT _dnGmxJIT,
        IERC20 _sGLP
    ) internal onlyInitializing {
        dnGmxJuniorVault = _dnGmxJuniorVault;
        dnGmxBatchingManager = _dnGmxBatchingManager;
        dnGmxJIT = _dnGmxJIT;
        sGLP = _sGLP;
        sGLP.approve(address(dnGmxJuniorVault), type(uint).max);
    }

    function deposit(uint256 amount, address receiver) external {
        dnGmxJIT.addLiquidity();
        sGLP.transferFrom(msg.sender, address(this), amount);
        dnGmxJuniorVault.deposit(amount, receiver);
        dnGmxJIT.removeLiquidity();
    }

    function executeBatchDeposit() external {
        dnGmxJIT.addLiquidity();
        dnGmxBatchingManager.executeBatchDeposit();
        dnGmxJIT.removeLiquidity();
    }
}

