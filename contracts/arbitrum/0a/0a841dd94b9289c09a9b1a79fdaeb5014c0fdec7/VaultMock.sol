// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IVault.sol";
import "./IAtlasMine.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./ITestERC20.sol";

contract VaultMock is IVault {
    IBattleflyAtlasStakerV02 public STAKER;

    constructor(address _staker, address _magic) {
        STAKER = IBattleflyAtlasStakerV02(_staker);
        ITestERC20(_magic).approve(_staker, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        ITestERC20(_magic).mint(100000e18, address(this));
    }

    function deposit(uint128 _amount, IAtlasMine.Lock lock) public {
        STAKER.deposit(_amount, lock);
    }

    function withdraw(uint256 depositId) public {
        STAKER.withdraw(depositId);
    }

    function requestWithdrawal(uint256 depositId) public {
        STAKER.requestWithdrawal(depositId);
    }

    function claim(uint256 depositId) public {
        STAKER.claim(depositId);
    }

    function isAutoCompounded(uint256) public pure override returns (bool) {
        return false;
    }

    function updatePosition(uint256) public override {}
}

