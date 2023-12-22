//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";

contract BBQPartyPublicPresale {
    uint256 public maxAllocation;

    address public owner;
    address public withdrawalAddress;
    address public usdc;

    bool public publicSaleOpen;
    uint256 public totalFund;
    uint256 public hardCap;

    mapping(address => bool) whitelistedAddress;
    mapping(address => uint256) currentPayments;

    constructor(address _usdc, address _withdrawalAddress) {
        owner = msg.sender;

        usdc = _usdc;
        withdrawalAddress = _withdrawalAddress;

        publicSaleOpen = false;

        maxAllocation = 1500_000_000; // 1500 USDC

        hardCap = 45000_000_000;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    function fillPresale(uint256 amount) public payable {
        require(publicSaleOpen, "Presale not open");
        require(amount <= maxAllocation, "Amount above maximum allocation");
        require(totalFund + amount <= hardCap, "Hardcap");
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
        currentPayments[msg.sender] += amount;
        totalFund += amount;
    }

    function withdraw() external onlyOwner {
        uint256 amount = IERC20(usdc).balanceOf(address(this));
        IERC20(usdc).transfer(withdrawalAddress, amount);
    }

    function setPresaleStatus(bool _status) external onlyOwner {
        publicSaleOpen = _status;
    }

    function setMaxAllocation(uint256 _maxAllocation) external onlyOwner {
        maxAllocation = _maxAllocation;
    }

    function setHardCap(uint256 _hardCap) external onlyOwner {
        hardCap = _hardCap;
    }

    function getAddressCurrentPayments(address _address) public view returns (uint256) {
        return currentPayments[_address];
    }

}
