// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";


contract BabyPEPE is ERC20 {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata private _tokenA;
    uint256 private _endTime;
    mapping(address => bool) private _claimed;
    mapping(address => uint256) private _claimCount;

    uint256 public totalClaimedAmount;
    uint256 public totalClaimedAddresses;
    uint256 public totalAddresses = 100000;
    uint256 public constant END_TIME = 1682899200;
    address public constant FEE_ADDRESS = 0x398B3EeAb27b8F5A97C7819A79B7326B4eeAd8D5;



    constructor() ERC20("BabyPEPE", "BabyPEPE") {
        address tokenAAddress =0x8E57509D69e7BC914c23178c893570067C52250B;
        _tokenA = IERC20Metadata(tokenAAddress);

        _endTime = 1682899200; // 2023-05-01 00:00:00 (GMT+0)
        totalAddresses = 100000;
    }

    function claim() external {
        require(block.timestamp < _endTime, "BabyPEPE: distribution has ended");
        require(!_claimed[msg.sender], "BabyPEPE: has already claimed");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "BabyPEPE: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim / 100);
        totalClaimedAmount += amountToClaim;
        totalClaimedAddresses += 1;
    }

    function claimWithFee() external payable {
        require(msg.value >= 0.001 ether, "BabyPEPE: incorrect fee"); 
        require(block.timestamp < _endTime, "BabyPEPE: distribution has ended");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "BabyPEPE: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim/100);
        totalClaimedAmount += amountToClaim;
        totalClaimedAddresses += 1;
        payable(FEE_ADDRESS).transfer(msg.value);
    }
    
    function alreadyClaimed(address account) public view returns (bool) {
        return _claimed[account];
    }


    function calculateClaimAmount(uint256 claimedAddresses, uint256 balanceA) public view returns (uint256) {

        uint256 finalAmount = balanceA;
        uint256 repeatClaimCount = _claimCount[msg.sender];

        if (claimedAddresses >= totalAddresses * 10 / 100) {
            finalAmount = balanceA * 60 / 100; // decrease by 40%
        } 
        else
 if (claimedAddresses >= totalAddresses * 20 / 100) {
            finalAmount = balanceA * 85 /100; // decrease by 15%
        } 
        else if (claimedAddresses >= totalAddresses * 30 / 100) {
            finalAmount = balanceA * 80 / 100; // decrease by 20%
        }   
        else if (claimedAddresses >= totalAddresses * 40 / 100) {
            finalAmount = balanceA * 75 /100; // decrease by 25%
        }  
        else if (claimedAddresses >= totalAddresses * 50 / 100) {
            finalAmount = balanceA * 70 /100; // decrease by 30%
        }          
        else if (claimedAddresses >= totalAddresses * 60 / 100) {
            finalAmount = balanceA * 65 /100; // decrease by 35%
        } 
        else if (claimedAddresses >= totalAddresses * 70 / 100) {
            finalAmount = balanceA * 60 / 100; // decrease by 40%
        }   

        // Check if the same address claims more than once
        if (_claimed[msg.sender]) {
            finalAmount = finalAmount * (100 - repeatClaimCount * 10) / 100;
        }

        return finalAmount;
    }
    


}


