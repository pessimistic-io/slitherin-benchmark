// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./BehaviorSafetyMethods.sol";
import "./console.sol";

struct DepositInfo {
    uint256 depositAmount;
    bool claimed;
}

contract ComponentLockerSwapper is Ownable, BehaviorSafetyMethods {
    bool public isClaimable;
    address public addressSourceToken;
    address public addressTargetToken;
    uint256 public amountSourceTokens;
    uint256 public amountTargetTokens;
    mapping(address => DepositInfo) depositors;

    constructor(address _addressSourceToken, address _addressTargetToken) {
        addressSourceToken = _addressSourceToken;
        addressTargetToken = _addressTargetToken;
    }

    function depositedSourceAmount(address _addr) public view returns (uint256) {
        return depositors[_addr].depositAmount;
    }

    function hasClaimed(address _addr) public view returns (bool) {
        return depositors[_addr].claimed;
    }

    function depositSourceTokens(uint256 _amount) public {
        require(isClaimable == false, "Can't deposit when claiming is in progress");
        require(_amount > 0, "You need to deposit some amount");
        IERC20(addressSourceToken).transferFrom(msg.sender, address(this), _amount);
        depositors[msg.sender].depositAmount += _amount;
        amountSourceTokens += _amount;
    }

    function withdrawSourceTokens(uint256 _amount) public {
        require(isClaimable == false, "Can't withdraw when claiming is in progress");
        require(_amount > 0, "You need to withdraw some amount");
        require(depositors[msg.sender].depositAmount >= _amount, "Nope");

        IERC20(addressSourceToken).transfer(msg.sender, _amount);
        depositors[msg.sender].depositAmount -= _amount;
        amountSourceTokens -= _amount;
    }

    function depositTargetTokens(uint256 _amount) public onlyOwner {
        amountTargetTokens += _amount;
        IERC20(addressTargetToken).transferFrom(msg.sender, address(this), _amount);
    }

    function setClaimable(bool _claimable) public onlyOwner {
        isClaimable = _claimable;
    }

    function claim() public {
        require(isClaimable, "Claiming didn't start");
        require(depositors[msg.sender].claimed == false, "You can claim only once");

        uint256 deposited = depositors[msg.sender].depositAmount;
        require(deposited > 0, "You didn't deposit anything");

        uint256 targetShare = (amountTargetTokens * deposited) / amountSourceTokens;

        IERC20(addressTargetToken).transfer(msg.sender, targetShare);
        depositors[msg.sender].claimed = true;
    }

    function adminWithdrawSourceTokens() public onlyOwner {
        IERC20(addressSourceToken).transfer(msg.sender, IERC20(addressSourceToken).balanceOf(address(this)));
    }

    function adminWithdrawTargetTokens() public onlyOwner {
        IERC20(addressTargetToken).transfer(msg.sender, IERC20(addressTargetToken).balanceOf(address(this)));
    }
}

