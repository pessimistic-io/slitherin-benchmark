// SPDX-License-Identifier:  WTFPL

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Strings.sol";
import "./Ownable.sol";

contract BurnMoneyForFun is ERC20, Ownable {
    address public uniswapV3Pool;
    uint256 public bootTime;
    uint256 public maxHoldingAmount;
    string public twitter;
    uint256 public roarCount;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _totalSupply,
        string memory _twitter
    ) ERC20(name, symbol) {
        _mint(msg.sender, _totalSupply);
        maxHoldingAmount = _totalSupply / 200;
        twitter = _twitter;
    }

    function updateSetting(
        address _uniswapV3Pool,
        uint256 _bootTime
    ) external onlyOwner {
        uniswapV3Pool = _uniswapV3Pool;
        bootTime = _bootTime;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from == uniswapV3Pool && from != address(0)) {
            require(
                block.timestamp > bootTime ||
                    super.balanceOf(to) + amount < maxHoldingAmount,
                "Anti Whale"
            );
            emit Roar(
                from,
                roarCount++,
                block.timestamp,
                "I am playing with candlestick charts for fun! Exciting. Yaaayaya~"
            );
        } else if (to == uniswapV3Pool && from != address(0)) {
            emit Roar(
                from,
                roarCount++,
                block.timestamp,
                "I am playing with candlestick charts for fun! Exciting. Yaaayaya~"
            );
        }
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    // Event to be emitted when a roar happens
    event Roar(
        address indexed from,
        uint256 indexed index,
        uint256 timestamp,
        string words
    );

    // Function to emit a Roar event with a fun message in multiple languages
}

