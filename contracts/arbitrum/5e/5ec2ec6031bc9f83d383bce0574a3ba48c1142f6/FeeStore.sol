// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IPYESwapFactory } from "./IPYESwapFactory.sol";
import { IPYESwapPair } from "./IPYESwapPair.sol";

abstract contract FeeStore {
    uint public swapFee;
    uint public adminFee;
    address public adminFeeAddress;
    address public adminFeeSetter;
    address public factoryAddress;
    mapping(address => address) public pairFeeAddress;

    event AdminFeeSet(uint adminFee, address adminFeeAddress);
    event SwapFeeSet(uint swapFee);
    event StableTokenUpdated(address token, bool isStable);

    constructor (
        address _factory, 
        uint256 _adminFee, 
        address _adminFeeAddress, 
        address _adminFeeSetter
    ) {
        factoryAddress = _factory;
        adminFee = _adminFee;
        adminFeeAddress = _adminFeeAddress;
        adminFeeSetter = _adminFeeSetter;
    }

    function setAdminFee(address _adminFeeAddress, uint _adminFee) external {
        require(msg.sender == adminFeeSetter, "PyeSwap: NOT_AUTHORIZED");
        require(_adminFee + 17 <= 100, "PyeSwap: EXCEEDS MAX FEE");
        adminFeeAddress = _adminFeeAddress;
        adminFee = _adminFee;
        swapFee = _adminFee + 17;
        emit AdminFeeSet(adminFee, adminFeeAddress);
        emit SwapFeeSet(swapFee);
    }

    function setAdminFeeSetter(address _adminFeeSetter) external {
        require(msg.sender == adminFeeSetter, "PyeSwap: NOT_AUTHORIZED");
        adminFeeSetter = _adminFeeSetter;
    }
}
