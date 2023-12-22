// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IERC20.sol";

contract Presale {
    uint public publicPrice;
    uint public privatePrice;
    uint public maxAlloc;

    address public owner;
    address public token;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    bool public presaleIsOpen;
    bool public claimIsOpen;

    mapping(address => uint) public alloc;
    mapping(address => bool) public isWhitelisted;

    uint public totalPublic;
    uint public totalPrivate;

    constructor(
        uint _publicPrice,
        uint _privatePrice,
        uint _maxAlloc,
        address _token
    ) {
        owner = msg.sender;
        publicPrice = _publicPrice;
        privatePrice = _privatePrice;
        maxAlloc = _maxAlloc;
        token = _token;
    }

    function enterPublic(uint _tokenAmount) public {
        require(presaleIsOpen == true, "Presale is closed");
        require(_tokenAmount > 0, "Wrong value");
        require(
            alloc[msg.sender] + _tokenAmount <= maxAlloc * 1e18,
            "Max alloc reached"
        );

        uint price = _tokenAmount * publicPrice / 1e18;
        IERC20(usdc).transferFrom(msg.sender, address(this), price);
        alloc[msg.sender] += _tokenAmount;
        totalPublic += _tokenAmount;
    }

    function enterPrivate(uint _tokenAmount) public {
        require(presaleIsOpen == true, "Presale is closed");
        require(isWhitelisted[msg.sender] == true, "Not whitelisted");
        require(_tokenAmount > 0, "Wrong value");
        require(
            alloc[msg.sender] + _tokenAmount <= maxAlloc * 1e18,
            "Max alloc reached"
        );

        uint price = _tokenAmount * privatePrice / 1e18;
        IERC20(usdc).transferFrom(msg.sender, address(this), price);
        alloc[msg.sender] += _tokenAmount;
        totalPrivate += _tokenAmount;
    }

    function claim() public {
        require(claimIsOpen == true, "Claim closed");
        require(alloc[msg.sender] > 0, "Nothing to claim");
        IERC20(token).transfer(msg.sender, alloc[msg.sender]);
        alloc[msg.sender] = 0;
    }

    function whitelistUser(address _user) public onlyOwner {
        isWhitelisted[_user] = true;
    }

    function whitelistTwenty(address[20] memory _users) public onlyOwner {
        for (uint i; i < 20; i++) {
            isWhitelisted[_users[i]] = true;
        }
    }

    function openPresale() public onlyOwner {
        presaleIsOpen = true;
    }

    function closePresale() public onlyOwner {
        presaleIsOpen = false;
    }

    function openClaim() public onlyOwner {
        claimIsOpen = true;
    }

    function closeClaim() public onlyOwner {
        claimIsOpen = false;
    }

    function userIsWhitelisted(address _user) public view returns (bool) {
        return isWhitelisted[_user];
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
}

