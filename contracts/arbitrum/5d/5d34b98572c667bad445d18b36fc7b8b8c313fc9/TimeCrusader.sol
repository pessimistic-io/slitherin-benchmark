// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract TimeCrusader is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 public period;
    uint256 public startAt;
    uint256 public endAt;

    event StartGame(uint256 indexed startAt, uint256 endAt, uint256 period);
    event BuyClick(address indexed buyer, uint8 amount);
    event Claim(
        address indexed winner,
        uint256 amount,
        address token,
        uint256 claimedAt
    );

    address public winner;
    address public tokenToClaim;

    uint256 public priceClick = 0.003 ether;
    address public team = 0xBA35f048FCddeDD09e79329C5A3A07AC5f792D41;
    uint8 public maxBuyAmount = 5;

    constructor() ERC20("Time Crusader", "TESAN") {
        _mint(msg.sender, 100_000 ether);
    }

    // all in second
    function startGame(
        uint256 _startAt,
        uint256 _endAt,
        uint256 _period
    ) external onlyOwner {
        require(
            block.timestamp <= _startAt,
            "The start must great of the block time"
        );
        require(_startAt <= _endAt, "The date start must great of endAt");
        require(isEnded(), "The game is not over");
        startAt = _startAt;
        endAt = _endAt;
        period = _period;
        emit StartGame(startAt, endAt, period);
    }

    function isEnded() public view returns (bool) {
        return block.timestamp >= endAt;
    }

    function buyClick(uint8 amount) external payable {
        require(
            amount > 0 && amount <= maxBuyAmount,
            "The amount is :maxBuyAmount"
        );
        require(msg.value >= priceClick * amount, "You do not have enough eth");
        payable(team).transfer(msg.value);
        emit BuyClick(msg.sender, amount);
    }

    function claimPrice() external {
        require(winner != address(0), "The winner is not defined");
        require(
            tokenToClaim != address(0),
            "The token claimable is not defined"
        );
        IERC20 token = IERC20(tokenToClaim);
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.transfer(winner, balance);
            winner = address(0);
            emit Claim(winner, balance, tokenToClaim, block.timestamp);
        }
    }

    function claimePriceEth() external {
        require(winner != address(0), "The winner is not defined");
        require(
            tokenToClaim == address(0),
            "The claim token is not to be defined"
        );
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(winner).transfer(balance);
            winner = address(0);
            emit Claim(winner, balance, address(0), block.timestamp);
        }
    }

    function setPrice(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Token allowance must be increased"
        );
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        tokenToClaim = token;
    }

    function setPriceETH() external payable onlyOwner {
        require(msg.value > 0, "The value cannot be null");
        tokenToClaim = address(0);
    }

    function setWinner(address winner_) external onlyOwner {
        winner = winner_;
    }

    function setPriceClick(uint256 price) external onlyOwner {
        priceClick = price;
    }

    function setTeam(address addr) external onlyOwner {
        team = addr;
    }

    receive() external payable {}
}

