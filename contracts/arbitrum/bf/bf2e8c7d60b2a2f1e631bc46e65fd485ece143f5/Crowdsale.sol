// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Ownable.sol";

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conforms
 * the base architecture for crowdsales. It is *not* intended to be modified / overridden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropriate to concatenate
 * behavior.
 */
contract Crowdsale is Context, ReentrancyGuard, Ownable {
    // The token being sold
    IERC20 public token;

    // Address where funds are collected
    address public wallet;

    uint public numerator;
    uint public denominator;

    uint public subjectRaised;

    mapping(address => uint) public purchasedAddresses;
    mapping(address => bool) public claimed;

    event TokenPurchased(address indexed user, uint value);
    event TokenClaimed(address indexed user, uint value);

    constructor(
        uint numerator_,
        uint denominator_,
        address wallet_,
        IERC20 token_
    ) {
        setParameters(numerator_, denominator_, wallet_, token_);
    }

    function setParameters(
        uint numerator_,
        uint denominator_,
        address wallet_,
        IERC20 token_
    ) public onlyOwner {
        require(numerator_ > 0 && denominator_ > 0, "Crowdsale: rate is 0");
        require(wallet_ != address(0), "Crowdsale: wallet is the zero address");
        numerator = numerator_;
        denominator = denominator_;
        wallet = wallet_;
        token = token_;
    }

    function setToken(IERC20 token_) external onlyOwner {
        require(
            address(token_) != address(0),
            "Crowdsale: token is the zero address"
        );
        token = token_;
    }

    function getTokenAmount(uint amount) public view returns (uint) {
        return (amount * numerator) / denominator;
    }

    function emergencyWithdraw(address token_) external onlyOwner {
        IERC20(token_).transfer(
            msg.sender,
            IERC20(token_).balanceOf(address(this))
        );
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH transfer failed");
    }
}

