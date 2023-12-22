// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Owned} from "./Owned.sol";
import "./IYieldHandler.sol";
import "./IDSRManager.sol";

contract DAIHandler is IYieldHandler {

    IDSRManager public constant DSR_MANAGER = IDSRManager(0x373238337Bfe1146fb49989fc222523f83081dDb);
    address constant DAI = 0x5F6AE08B8AeB7078cf2F96AFb089D7c9f51DA47d;
    address constant KEIMANAGER = 0xd513E4537510C75E24f941f159B7CAFA74E7B3B9;

    uint256 public deposited;
    uint256 public currentEpochYield;

    function deposit(address _from, uint256 _amount) public {
        ERC20(DAI).transferFrom(KEIMANAGER, address(this), _amount);
        ERC20(DAI).approve(address(DSR_MANAGER), _amount);
        DSR_MANAGER.join(KEIMANAGER, _amount);
    }

    function withdraw(address _from, uint256 _amount) public {
        DSR_MANAGER.exit(KEIMANAGER, _amount);
    }

    function getBalance(address _address) public returns(uint256) {
        uint256 dsrBalance = DSR_MANAGER.daiBalance(_address);
        return dsrBalance;
    }
}
