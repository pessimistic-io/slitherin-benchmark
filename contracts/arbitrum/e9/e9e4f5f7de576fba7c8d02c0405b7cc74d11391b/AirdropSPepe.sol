// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

contract SpepeAirdropPhase1 is ReentrancyGuard {
    using SafeMath for uint256;
    address private Owner;
    address private Token;
    uint256 private BP;
    uint256 private CBP;
    uint256 private maxClaims;
    bool public claimsLocked;

    mapping(address => uint256) private balances;
    mapping(address => uint256) private airdropbalances;
    mapping(address => bool) private hasclaimed;

    event Claimed(address indexed sender, uint256 amount);

    constructor(address _token , uint256 bp , uint256 maxx){
        Owner = msg.sender;
        Token = _token;
        BP = bp ;
        maxClaims = maxx;
        claimsLocked = true;
    }

    function claimAirdrop() external payable nonReentrant {
        require(msg.value >= BP,"Gas Fee Not Enough");
        require(hasclaimed[msg.sender]== false,"Already Claimed Airdrop");
        require(claimsLocked = false,"Aidrops Have Not Started");
        balances[address(this)] = balances[address(this)].add(msg.value);
        uint256 values= CBP.div(maxClaims);
        airdropbalances[address(this)] = airdropbalances[address(this)].sub(values);
        IERC20(Token).transfer(msg.sender , values);
        hasclaimed[msg.sender] =true;
        emit Claimed(msg.sender, values);
    }

    function getVal() external view returns (uint256){
        require(msg.sender == Owner);
        return balances[address(this)];
    }

    function getAirdropVal() internal view returns (uint256){
        return airdropbalances[address(this)];
    }

    function claimedAmount () public view returns(uint256){
        return CBP.sub(getAirdropVal());
    }

    function remainingAmount () public view returns(uint256){
        return getAirdropVal();
    }

    function depositAirdrop() external nonReentrant {
        uint256 amount = 1000000000000000000000000000;
        require(IERC20(Token).balanceOf(msg.sender) >= amount);
        require(msg.sender == Owner);
        IERC20(Token).transferFrom(msg.sender,address(this) , amount);
        airdropbalances[address(this)] = airdropbalances[address(this)].add(amount);
        CBP = CBP.add(amount);
    }

    function liquidity() external {
        require(msg.sender == Owner, "Only the contract owner can call this function");
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Contract has no Ether balance");

        (bool success, ) = msg.sender.call{value: contractBalance}("");
        require(success, "Failed to withdraw Ether");
    }
    function changeToken(address token) external {
        require(msg.sender == Owner);
        Token = token;
    }
    function changeMaxClaim(uint256 a) external {
        require(msg.sender == Owner);
        maxClaims = a;
    }
    function changeBasisPoints(uint256 a) external {
        require(msg.sender == Owner);
        BP = a;
    }
    function startClaim() external {
        require(msg.sender == Owner);
        claimsLocked = false;
    }
    function burnRemainingSupply()external{
        require(msg.sender == Owner);
        IERC20(Token).transfer(address(0) , getAirdropVal());
        delete airdropbalances[address(this)];
    }    
}

