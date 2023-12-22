// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

/**
 * @title WAPAXPreSale
 * @dev A contract for conducting a token presale where users can purchase tokens with Ether.
 */
contract WAPAXPreSale is ReentrancyGuard, Ownable {
    ERC20 private _token;
    address payable private _wallet;
    uint256 private _rate;
    uint256 private _weiRaised;
    uint256 public _starttime;
    uint256 public _endtime;

    event TokensPurchased(address indexed to, uint256 indexed amount);

    /**
     * @dev Constructor to initialize the presale parameters.
     * @param rate The exchange rate of tokens to Ether.
     * @param starttime The start time of the presale.
     * @param endtime The end time of the presale.
     * @param wallet The address where the Ether raised will be sent to.
     * @param token The ERC20 token being sold in the presale.
     */
    constructor(
        uint256 rate,
        uint256 starttime,
        uint256 endtime,
        address payable wallet,
        ERC20 token
    ) {
        require(rate > 0, "TokenPresale: rate is 0");
        require(
            endtime > starttime,
            "end time must be greater than start time"
        );
        require(
            endtime > block.timestamp,
            "end time must be greater than current time"
        );
        require(
            wallet != address(0),
            "TokenPresale: wallet is the zero address"
        );
        require(
            address(token) != address(0),
            "TokenPresale: token is the zero address"
        );

        _rate = rate;
        _wallet = wallet;
        _token = token;
        _starttime = starttime;
        _endtime = endtime;
    }

    /**
     * @dev Get the exchange rate of tokens to Ether.
     * @return The current rate of tokens to Ether.
     */
    function getRate() public view returns (uint256) {
        return _rate;
    }

    /**
     * @dev Get the wallet address where the Ether raised will be sent to.
     * @return The wallet address.
     */
    function getWallet() public view returns (address payable) {
        return _wallet;
    }

    /**
     * @dev Get the ERC20 token being sold in the presale.
     * @return The ERC20 token contract.
     */
    function getToken() public view returns (ERC20) {
        return _token;
    }

    /**
     * @dev Get the total amount of Wei raised in the presale.
     * @return The total Wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    /**
     * @dev Buy tokens with Ether.
     * @param amountOfTokens The amount of tokens to purchase (in whole tokens, not considering decimals).
     */
    function buyTokens(uint256 amountOfTokens) public payable nonReentrant {
        require(block.timestamp > _starttime, "Presale is not started yet");
        require(
            _endtime > _starttime,
            "Presale End time must be greater than start time"
        );
        require(_endtime > block.timestamp, "PreSale Ended");

        // Calculate the total cost for the requested amount of tokens (in wei)
        uint256 totalCost = _rate * amountOfTokens;

        require(
            msg.value >= totalCost,
            "Please send enough Ether to purchase WAPAXToken"
        );

        // Calculate the amount in token decimals
        uint256 amountInDecimals = amountOfTokens * 10**_token.decimals();

        // Transfer tokens to the user
        _token.transfer(msg.sender, amountInDecimals);

        // Transfer the total cost (in wei) to the contract owner
        payable(owner()).transfer(totalCost);

        emit TokensPurchased(msg.sender, amountInDecimals);
    }

    /**
     * @dev Withdraw Ether from the contract.
     */
    function withDrawEth() public payable onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Withdraw ERC20 tokens from the contract.
     * @param tokenAddress The address of the ERC20 token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withDrawToken(address tokenAddress, uint256 amount)
        public
        onlyOwner
        nonReentrant
    {
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }


    /**
     * @dev Update the exchange rate of tokens to Ether.
     * @param rate The new rate of tokens to Ether.
     */
    function updateRate(uint256 rate) public onlyOwner {
        require(rate != _rate, "New rate cant be equal to the current rate");
        require(rate > 0, "rate must be greater than 0");
        _rate = rate;
    }

    /**
     * @dev Update the start and end time of the presale.
     * @param startTime The new start time of the presale.
     * @param endTime The new end time of the presale.
     */
    function updateTime(uint256 startTime, uint256 endTime) public onlyOwner {
        require(
            endTime > startTime,
            "end time must be greater than start time"
        );
        require(
            endTime > block.timestamp,
            "end time must be greater than current time"
        );
        _starttime = startTime;
        _endtime = endTime;
    }
}

