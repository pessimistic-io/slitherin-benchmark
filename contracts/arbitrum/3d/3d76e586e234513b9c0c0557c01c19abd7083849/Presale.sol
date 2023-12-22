// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./MerkleProof.sol";

contract Presale {
    bytes32 public merkleRoot =
        0x68a44648f98480974c7be321c0cc67ec23541106ae7abb7a7395dd777b5e24d9;

    uint public publicPrice; // Divide by 100 to get actual value
    uint public privatePrice; // Divide by 100 to get actual value
    uint public publicMaxDeposit;
    uint public privateMaxDeposit;

    uint public publicRaised;
    uint public privateRaised;

    address public owner;
    address public token;
    address public stable;

    bool public presaleIsOpen;
    bool public claimOpen;

    mapping(address => uint) public alloc;
    mapping(address => uint) public deposit;

    constructor(
        uint _publicPrice,
        uint _privatePrice,
        uint _publicMaxDeposit,
        uint _privateMaxDeposit,
        address _token,
        address _stable
    ) {
        owner = msg.sender;
        publicPrice = _publicPrice;
        privatePrice = _privatePrice;
        publicMaxDeposit = _publicMaxDeposit;
        privateMaxDeposit = _privateMaxDeposit;
        token = _token;
        stable = _stable;
    }

    function enterPublic(uint _usdAmount) public {
        require(_usdAmount > 0, "Wrong value");
        require(presaleIsOpen == true, "Presale is closed");
        require(
            deposit[msg.sender] + _usdAmount <= publicMaxDeposit,
            "Max deposit reached"
        );

        IERC20(stable).transferFrom(msg.sender, owner, _usdAmount);
        deposit[msg.sender] += _usdAmount;

        // Update Alloc
        uint tokenAmt = (_usdAmount * 100) / publicPrice;
        alloc[msg.sender] += tokenAmt;

        publicRaised += _usdAmount;
    }

    function enterPrivate(
        uint _usdAmount,
        bytes32[] calldata _merkleProof
    ) public {
        require(_usdAmount > 0, "Wrong value");
        require(presaleIsOpen == true, "Presale is closed");
        require(
            deposit[msg.sender] + _usdAmount <= privateMaxDeposit,
            "Max alloc reached"
        );

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof"
        );

        IERC20(stable).transferFrom(msg.sender, owner, _usdAmount);
        deposit[msg.sender] += _usdAmount;

        // Update Alloc
        uint tokenAmt = (_usdAmount * 100) / privatePrice;
        alloc[msg.sender] += tokenAmt;

        privateRaised += _usdAmount;
    }

    function claim() public {
        require(claimOpen == true, "Claim not allowed");
        require(alloc[msg.sender] > 0, "Nothing to claim");
        IERC20(token).transfer(msg.sender, alloc[msg.sender]);
        alloc[msg.sender] = 0;
    }

    function openClaim() public onlyOwner {
        require(presaleIsOpen == false, "Presale is open");
        claimOpen = true;
    }

    function openPresale() public onlyOwner {
        presaleIsOpen = true;
    }

    function closePresale() public onlyOwner {
        presaleIsOpen = false;
    }

    function setTokenAddress(address _address) public onlyOwner {
        token = _address;
    }

    function setOwner(address _address) public onlyOwner {
        owner = _address;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
}

