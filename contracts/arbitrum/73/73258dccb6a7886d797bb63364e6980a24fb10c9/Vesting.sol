// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafeERC20.sol";
import "./IInscriptionFactory.sol";
import "./TransferHelper.sol";
import "./IInitialFairOffering.sol";

interface Burnable {
    function burn(address sender, uint amount) external;
}

contract Vesting {
    IInscriptionFactory public inscriptionFactory;

    address public tokenAddress;  
    uint public startTime;
    uint public duration;

    mapping(address => uint) public allocation;
    mapping(address => uint) public claimed;
    uint public totalAllocation = 0;
    uint public totalClaimed = 0;

    event Add(address sender, uint amount);
    event Remove(address sender, uint amount);
    event Claim(address sender, uint amount);

    constructor(
        address inscriptionFactory_,
        uint startTime_, 
        uint duration_
    ) {
        inscriptionFactory = IInscriptionFactory(inscriptionFactory_);
        startTime = startTime_;
        duration = duration_;
    }

    function setTokenAddress(address _tokenAddress) public {
        require(msg.sender == address(inscriptionFactory), "Call only from factory");
        tokenAddress = _tokenAddress;
    }

    function addAllocation(address recipient, uint amount) public {
        (IInscriptionFactory.Token memory fercToken, ,) = inscriptionFactory.getIncriptionByAddress(tokenAddress);
        require(fercToken.addr == tokenAddress, "token not exist");
        require(msg.sender == fercToken.addr, "call must from token");
        allocation[recipient] += amount;
        totalAllocation += amount;
        emit Add(recipient, amount);
    }

    function removeAllocation(address recipient, uint amount) public {
        (IInscriptionFactory.Token memory fercToken, ,) = inscriptionFactory.getIncriptionByAddress(tokenAddress);
        require(msg.sender == fercToken.ifoContractAddress, "call must from fto contract");
        require(fercToken.addr == tokenAddress, "token not exist");
        require(allocation[recipient] >= amount, "allocation is not enough");
        allocation[recipient] -= amount;
        totalAllocation -= amount;
        Burnable(fercToken.addr).burn(address(this), amount);
        emit Remove(recipient, amount);
    }

    function claim() external {
        (IInscriptionFactory.Token memory fercToken, ,) = inscriptionFactory.getIncriptionByAddress(tokenAddress);
        require(fercToken.addr == tokenAddress, "token not exist");
        require(block.timestamp >= startTime, "LinearVesting: has not started");
        require(!fercToken.isIFOMode || IInitialFairOffering(fercToken.ifoContractAddress).liquidityAdded(), "Only workable after public liquidity added");
        uint amount = _available(msg.sender);
        require(amount > 0, "Available amount is zero");
        TransferHelper.safeTransfer(fercToken.addr, msg.sender, amount);
        claimed[msg.sender] += amount;
        totalClaimed += amount;
        emit Claim(msg.sender, amount);
    }

    function available(address address_) external view returns (uint) {
        return _available(address_);
    }

    function released(address address_) external view returns (uint) {
        return _released(address_);
    }

    function outstanding(address address_) external view returns (uint) {
        return allocation[address_] - _released(address_);
    }

    function _available(address address_) internal view returns (uint) {
        return _released(address_) - claimed[address_];
    }

    function _released(address address_) internal view returns (uint) {
        if (block.timestamp < startTime || allocation[address_] == 0) {
            return 0;
        } else {
            if (block.timestamp > startTime + duration) {
                return allocation[address_];
            } else {
                return allocation[address_] * (block.timestamp - startTime) / duration;
            }
        }
    }
}
