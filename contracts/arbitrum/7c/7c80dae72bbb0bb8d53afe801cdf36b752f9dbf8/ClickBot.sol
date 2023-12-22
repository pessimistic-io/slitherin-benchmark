// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";

/**
 * @title ClickBotToken
 * @dev Implementation of the ClickBotToken
 */
contract ClickBotToken is ERC20, Ownable {
    uint256 public constant TAX_FEE = 5; 
    uint256 public ticketPrice;
    address public teamAddress;
    IUniswapV2Router02 public uniswapV2Router;
    mapping(address => bool) public hasBoughtTicket;
    mapping(address => bool) public isExcludedFromFee;

    event TicketBought(address indexed buyer);
    event WinnerPaid(address indexed winner, uint256 amount);

    /**
     * @dev Sets the values for {ticketPrice}, {initialSupply}, {teamAddress} and {uniswapV2Router}, 
     * initializes {ERC20} with a name and symbol.
     */
    constructor(
        uint256 _ticketPrice, 
        uint256 initialSupply, 
        address _teamAddress, 
        address _uniswapV2Router
    ) 
    ERC20("tst", "tst") 
    {
        ticketPrice = _ticketPrice;
        teamAddress = _teamAddress;
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Returns the current jackpot
     */
    function getCurrentJackpot() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Allows user to buy a ticket if they have enough tokens
     */
    function buyTicket() external {
        require(balanceOf(msg.sender) >= ticketPrice, "Not enough tokens to buy a ticket.");

        uint256 tokensToBurn = ticketPrice / 2;
        uint256 tokensToSwap = ticketPrice - tokensToBurn;

        // Burn half of the tokens
        _burn(msg.sender, tokensToBurn);

        // Swap the other half for ETH and send to contract
        swapTokensForEth(tokensToSwap);

        // Record that the user has bought a ticket
        hasBoughtTicket[msg.sender] = true;

        emit TicketBought(msg.sender);
    }

    /**
     * @dev Allows the owner to change the ticket price
     */
    function changeTicketPrice(uint256 _newPrice) external onlyOwner {
        ticketPrice = _newPrice;
    }

    /**
     * @dev Allows the owner to pay the winner
     */
    function payWinner(address _winner) external onlyOwner {
        uint256 balance = address(this).balance;
        uint256 payout = balance / 2;

        require(payout > 0, "Not enough tokens to pay the winner.");
        require(hasBoughtTicket[_winner], "Winner has not bought a ticket.");

        // Transfer half the ETH from this contract to the winner
        (bool sent, ) = _winner.call{value: payout}("");
        require(sent, "Failed to send ETH to winner");

        emit WinnerPaid(_winner, payout);
    }

    /**
     * @dev Overrides ERC20's transfer function
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        transferTokens(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Overrides ERC20's transferFrom function
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        transferTokens(sender, recipient, amount);
        super.transferFrom(sender, recipient, amount);
        return true;
    }

    /**
     * @dev Transfers tokens taking into account the tax fee
     */
    function transferTokens(address sender, address recipient, uint256 amount) internal {
        uint256 taxAmount = isExcludedFromFee[sender] || isExcludedFromFee[recipient] ? 0 : (amount * TAX_FEE) / 100;
        uint256 sendAmount = amount - taxAmount;

        super.transfer(recipient, sendAmount);
        if(taxAmount > 0){
            // Swap tax for ETH
            swapTokensForEth(taxAmount);

            // Distribute ETH
            uint256 teamShare = (address(this).balance * 25) / 100;
            uint256 contractShare = address(this).balance - teamShare;

            (bool sentToTeam, ) = teamAddress.call{value: teamShare}("");
            require(sentToTeam, "Failed to send ETH to team");

            (bool sentToContract, ) = address(this).call{value: contractShare}("");
            require(sentToContract, "Failed to send ETH to contract");
        }
    }

    /**
     * @dev Swap tokens for ETH
     */
    function swapTokensForEth(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // Make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Allows the owner to withdraw tokens from the contract
     */
    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        uint256 contractBalance = balanceOf(address(this));

        require(contractBalance >= amount, "Not enough tokens in the contract");

        transferTokens(address(this), to, amount);
    }

    /**
     * @dev Allows the owner to exclude an account from fee
     */
    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }
}

