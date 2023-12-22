// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract XirtamShit is ERC20, Ownable {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata private _tokenA;
    uint256 private _endTime;
    mapping(address => bool) private _claimed;
    mapping(address => uint256) private _claimCount;
    mapping(address => address) private _referral;

    uint256 public totalClaimedAmount;
    uint256 public totalClaimedAddresses;
    uint256 public totalAddresses = 10000;
    uint256 public constant END_TIME = 1682899200;
    address public constant FEE_ADDRESS = 0x7f400208E3419e26425DDf4D30Ef930cD54d7E0D;
    address public constant Block_ADDRESS = 0xD07cc82cEd08a2B10A244f02354E6E0199E6CF92;

    constructor() ERC20("XirtamShit", "XirtamShit") {
        address tokenAAddress = 0xe73394F6a157A0Fa656Da2b73BbEDA85c38dfDeC;
        _tokenA = IERC20Metadata(tokenAAddress);

        _endTime = 1683676800; // 2023-05-10 00:00:00 (GMT+0)
        totalAddresses = 10000;
        transferOwnership(msg.sender);
    }

    function transferOwnershipToAddress(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }

    function claim() external {
        require(block.timestamp < _endTime, "XirtamShit: distribution has ended");
	require(msg.sender != Block_ADDRESS, "XirtamShit: this address is not allowed to claim");
        require(!_claimed[msg.sender], "XirtamShit: has already claimed");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "XirtamShit: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim / 10);
        totalClaimedAmount += amountToClaim;
        totalClaimedAddresses += 1;
    }


    function claimWithFee() external payable {
	require(msg.sender != Block_ADDRESS, "XirtamShit: this address is not allowed to claim");
        require(msg.value >= 0.01 ether, "XirtamShit: incorrect fee"); 
        require(block.timestamp < _endTime, "XirtamShit: distribution has ended");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "XirtamShit: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim/10);
        totalClaimedAmount += amountToClaim;
        totalClaimedAddresses += 1;
        payable(FEE_ADDRESS).transfer(msg.value);
    }


    function claim_ref(address referral) external {
	require(msg.sender != Block_ADDRESS, "XirtamShit: this address is not allowed to claim");
        require(block.timestamp < _endTime, "XirtamShit: distribution has ended");
        require(!_claimed[msg.sender], "XirtamShit: has already claimed");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "XirtamShit: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        if (referral != msg.sender) {
            _mint(referral, amountToClaim / 10); // give 10% to the referrer
        }
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim / 10);
        totalClaimedAmount += amountToClaim;
        totalClaimedAddresses += 1;
    }


    function claimWithFee_ref(address referral) external payable {
	require(msg.sender != Block_ADDRESS, "XirtamShit: this address is not allowed to claim");
        require(msg.value >= 0.01 ether, "XirtamShit: incorrect fee"); 
        require(block.timestamp < _endTime, "XirtamShit: distribution has ended");
        uint256 balanceA = _tokenA.balanceOf(msg.sender);
        require(balanceA > 0, "XirtamShit: no tokens to claim");
        uint256 amountToClaim = calculateClaimAmount(totalClaimedAddresses, balanceA);
        _claimed[msg.sender] = true;
        _claimCount[msg.sender] += 1;
        if (referral != msg.sender) {
            _mint(referral, amountToClaim / 10); // give 10% to the referrer
        }
        _mint(msg.sender, amountToClaim);
        _mint(FEE_ADDRESS, amountToClaim/10);
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
            finalAmount = balanceA * 90 / 100; // decrease by 10%
        } 
        else if (claimedAddresses >= totalAddresses * 20 / 100) {
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

	finalAmount = finalAmount  * 10000;

        return finalAmount;
    }
    


}


