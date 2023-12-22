// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {Ownable} from "./Ownable.sol";

contract arbiBallTreasury is Ownable{
    
    address public arbiBall;
    uint16 public ownerFee = 2500; // 25%
    
    event OwnerFeeUpdated(uint16 _ownerFee);
    event MaxRaffleAmountUpdated(uint32 _raffleId, uint256 _amount);
    event ValidCallerUpdated(address _caller, bool _value);
    event WithdrawFromRaffle(address _user, uint32 _raffleId, uint256 _amount);
    event DepositFromRaffle(uint32 _raffleId, uint256 _amount);
    event WithdrawOwnerFee(uint32 _raffleId, uint256 _amount);
    
    mapping (address => bool) public isValidCaller;
    mapping (uint32 => uint256) public ownerFeeAccumulatedInRaffle;
    mapping (uint32 => uint256) public fundsAccumulatedInRaffle; // Can remove this; need to think more about it
    mapping (uint32 => uint256) public amountWithdrawnFromRaffle;
    mapping (uint32 => uint256) public maxRaffleAmount;
    
    modifier validateCall () {
        require(isValidCaller[msg.sender] || msg.sender == address(arbiBall), "Treasury: Caller is not valid");
        _;
    }
    
    constructor(address _arbiBall) {
        arbiBall = _arbiBall;
    }
    
    function withdrawFromRaffle(address payable _user, uint32 _raffleId, uint256 _amount) external validateCall{
        require(_user != address(0), "Token address cannot be 0");
        require(_amount > 0, "Amount should be greater than 0");
        require(
            amountWithdrawnFromRaffle[_raffleId] + _amount <= maxRaffleAmount[_raffleId],
            "Amount exceeds max raffle amount"
        );
        amountWithdrawnFromRaffle[_raffleId] += _amount;
        _user.transfer(_amount);
        emit WithdrawFromRaffle(_user, _raffleId, _amount);
    }
    
    function depositFromRaffle(uint32 _raffleId) external payable validateCall{
        require(msg.value > 0, "Amount should be greater than 0");
        uint256 ownerFeeAmount = msg.value * ownerFee / 10000;
        ownerFeeAccumulatedInRaffle[_raffleId] += ownerFeeAmount;
        fundsAccumulatedInRaffle[_raffleId] += msg.value - ownerFeeAmount;
        emit DepositFromRaffle(_raffleId, msg.value);
    }
    
    function withdrawOwnerFee(uint32 _raffleId, address _to) external onlyOwner {
        require(ownerFeeAccumulatedInRaffle[_raffleId] > 0, "No owner fee accumulated");
        uint256 amount = ownerFeeAccumulatedInRaffle[_raffleId];
        ownerFeeAccumulatedInRaffle[_raffleId] = 0;
        payable(_to).transfer(amount);
        emit WithdrawOwnerFee(_raffleId, amount);
    }
    
    function depositToARaffle(uint32 _raffleId) external payable {
        require(msg.value > 0, "Amount should be greater than 0");
        emit DepositFromRaffle(_raffleId, msg.value);
    }
    
    // Setter
    
    function setArbiBall(address _arbiBall) external onlyOwner {
        arbiBall = _arbiBall;
    }
    
    function setOwnerFee(uint16 _ownerFee) external onlyOwner {
        ownerFee = _ownerFee;
        emit OwnerFeeUpdated(_ownerFee);
    }
    
    function setValidCaller(address _caller, bool _value) external onlyOwner {
        isValidCaller[_caller] = _value;
        emit ValidCallerUpdated(_caller, _value);
    }
    
    function setMaxRaffleAmount(uint32 _raffleId, uint256 _amount) external validateCall{
        maxRaffleAmount[_raffleId] = _amount;
        emit MaxRaffleAmountUpdated(_raffleId, _amount);
    }
    
    // Getter
    
    function getFundsAccumulatedInRaffle(uint32 _raffleId) external view returns(uint256) {
        return fundsAccumulatedInRaffle[_raffleId];
    }
    
}

