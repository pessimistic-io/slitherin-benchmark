// SPDX-License-Identifier: The Unlicense
pragma solidity 0.8.17;

import "./Owned.sol";
import "./Cancelled.sol";

/* This contract is to fuel the cancellors.

Users may send up to 0.1 ETH directly to the contract to receive 51,922,968,585,348 CANCEL per ETH sent (i.e. max 5,192,296,858,534.8 CANCEL). 

By sending ETH tokens to this contract you understand that Cancelled and the Cancellator are unaudited and purely provided for entertainment purposes, 
that the developers of these contracts have not provided financial or legal advice to you or anyone,
and you accept full responsbility for your actions and no one else. 
Cancelled and the Cancellatoru may not be used by individuals from any entity or individual under financial sanctions by the United States of America and/or the European Union (EU) or any member state of the EU. 

By interacting with this contract you agree to hold harmless, defend and indemnify the developers from any and all claims made by you arising from injury or loss due to your use of Cancelled and/or the Cancellator.

There are only minimal safety functions on this contract, and any tokens sent here should be considered permanently unrecoverable.

Prepare to be cancelled!

*/

interface IUniswapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract Cancellator is Owned(msg.sender) {

    uint256         public constant RATE = 51_922_968_585_348; //
    uint256         public constant MAX_CLAIM = 0.1 ether; //maximum number of ETH to be received

    uint256         public immutable CANCELLED_FOR_LP;

    Cancelled       public immutable CANCELLED;
    IUniswapRouter  public immutable ROUTER;
    
    mapping(address => uint256) public claims;

    constructor() {
        ROUTER = IUniswapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        
        CANCELLED = new Cancelled(ROUTER.factory(), ROUTER.WETH());
        CANCELLED_FOR_LP = type(uint112).max / 10; //max amount of CANCELLED that this contract that can be claimed
        
    }

    event LPAdded(uint amountToken, uint amountETH, uint liquidity);

    receive() external payable {
        require(msg.value <= MAX_CLAIM, "SENT_TOO_MUCH"); // user cannot send more than 0.1 ETH

        uint256 amt_to_release = msg.value * RATE; // calculate how much CANCELLED is to be sent
        require(CANCELLED.balanceOf(address(this)) - CANCELLED_FOR_LP >= amt_to_release, "INSUFFICIENT_ETH"); // make sure that there is enough CANCELLED in this contract

        require((claims[msg.sender]+amt_to_release) <= RATE * MAX_CLAIM, "ALREADY_CLAIMED"); // make sure that the user has not already claimed more than 5bn CANCELLED from this address

        unchecked{
            claims[msg.sender] += amt_to_release; // increase the counter for the amount being released in this transaction
        }

        CANCELLED.transfer(msg.sender, amt_to_release); // transfer the CANCELLED to the caller's address
    }

    function fillLP(uint256 ethAmt, uint256 CANCELLEDAmt, uint256 CANCELLEDAmtMin) public onlyOwner {

        CANCELLED.approve(address(ROUTER), CANCELLEDAmt);

        (uint amountToken, uint amountETH, uint liquidity) = ROUTER.addLiquidityETH{value: ethAmt}(address(CANCELLED), CANCELLEDAmt, CANCELLEDAmtMin, ethAmt, address(0xdead), block.timestamp+3600);

        CANCELLED.start();

        emit LPAdded(amountToken, amountETH, liquidity);

    }

}
