// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

contract PrivateCrowdsale is Ownable {
    ERC20 public token;
    ERC20 public usdc;
    address payable public wallet;
    uint256 public rate = 3;
    uint256 public openingTime;
    uint256 public closingTime;
    mapping(address => bool) public whitelist;

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    constructor(
        uint256 _openingTime,
        uint256 _closingTime,
        address payable _wallet,
        ERC20 _token,
        ERC20 _usdc,
        address _owner
    ) Ownable(_owner) {
        require(_openingTime >= block.timestamp);
        require(_closingTime >= _openingTime);
        require(_wallet != address(0));
        require(address(_token) != address(0));
        require(address(_usdc) != address(0));

        openingTime = _openingTime;
        closingTime = _closingTime;
        wallet = _wallet;
        token = _token;
        usdc = _usdc;
    }

    modifier isWhitelisted(address _beneficiary) {
        require(whitelist[_beneficiary], "Beneficiary not whitelisted.");
        _;
    }

    modifier onlyWhileOpen {
        require(block.timestamp >= openingTime && block.timestamp <= closingTime, "Crowdsale is closed.");
        _;
    }

    function addToWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = true;
    }

    function addManyToWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    function removeFromWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = false;
    }

    function buyTokens(address _beneficiary, uint256 _usdcAmount) external isWhitelisted(_beneficiary) onlyWhileOpen {
        require(_usdcAmount > 0, "Amount should be greater than 0");

        uint256 tokens = _getTokenAmount(_usdcAmount);

        require(usdc.transferFrom(msg.sender, wallet, _usdcAmount), "Failed to transfer USDC from buyer");
        require(token.transferFrom(wallet, _beneficiary, tokens), "Failed to transfer tokens to beneficiary");

        emit TokenPurchase(msg.sender, _beneficiary, _usdcAmount, tokens);
    }

    function _getTokenAmount(uint256 usdcAmount) internal pure returns (uint256) {
        // Price of 1 ROSA in USDC is 3, with ROSA having 18 decimals and USDC 6 decimals
        return (usdcAmount * 10**12) / 3;
    }

    function hasClosed() public view returns (bool) {
        return block.timestamp > closingTime;
    }
}

