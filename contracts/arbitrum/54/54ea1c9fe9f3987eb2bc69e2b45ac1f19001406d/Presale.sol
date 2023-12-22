// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";

/**
 * @title Presale
 * Presale allows investors to make
 * token purchases and assigns them tokens based
 * on a token per ETH rate. Funds collected are forwarded to a wallet
 * as they arrive.
 */

contract Presale is Pausable, Ownable {
    using SafeMath for uint256;

    // The token being sold
    IERC20 public token;
    address public crowdsaleAddress;

    // amount of raised money in wei
    uint256 public weiRaised;

    // cap above which the crowdsale is ended
    uint256 public cap;

    uint256 public minInvestment;

    uint256 public rate;

    bool public isFinalized;

    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 amount
    );

    /**
     * event for signaling finished crowdsale
     */
    event Finalized();

    /**
     * crowdsale constructor
     * @param _minInvestment is the minimum amount of ether that can be sent to the contract
     * @param _cap above which the crowdsale is closed
     * @param _rate is the amounts of tokens given for 1 ether
     */

    constructor(
        address _token,
        address _crowdsaleAddress,
        uint256 _minInvestment,
        uint256 _cap,
        uint256 _rate
    ) {
        require(_minInvestment >= 0);
        require(_cap > 0);

        token = IERC20(_token);
        crowdsaleAddress = _crowdsaleAddress;
        rate = _rate;
        minInvestment = _minInvestment; //minimum investment in wei
        cap = _cap ; //cap in wei
    }

    // fallback function to buy tokens
    receive() external payable {
        buyTokens(msg.sender);
    }

    /**
     * Low level token purchse function
     * @param beneficiary will recieve the tokens.
     */
    function buyTokens(address beneficiary) public payable whenNotPaused {
        require(beneficiary != address(0x0));
        require(validPurchase());

        uint256 weiAmount = msg.value;
        // update weiRaised
        weiRaised = weiRaised.add(weiAmount);
        // compute amount of tokens created
        uint256 tokens = weiAmount.mul(rate);
        token.transferFrom(crowdsaleAddress, beneficiary, tokens);

        emit TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);
    }

    // return true if the transaction can buy tokens
    function validPurchase() internal returns (bool) {
         uint256 weiAmount = weiRaised.add(msg.value);
        bool notSmallAmount = msg.value >= minInvestment;
        bool withinCap = cap >= weiAmount.mul(rate) ;
        return (withinCap && notSmallAmount);
    }

    //allow owner to finalize the presale once the presale is ended
    function finalize() public onlyOwner {
        require(!isFinalized);
        require(hasEnded());
        emit Finalized();
        isFinalized = true;
    }

    //return true if crowdsale event has ended
    function hasEnded() public view returns (bool) {
        bool capReached = (weiRaised.mul(rate) >= cap);
        return capReached;
    }

    // withdraw eth
    function withdrawTo(
        address payable account,
        uint256 weiAmount
    ) public onlyOwner returns (bool) {
        require(account != address(0x0));
        weiRaised = weiRaised.sub(weiAmount);
        account.transfer(weiAmount);
        return true;
    }
}

