pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract ElonsLadies is Ownable, ERC20 {
    bool public limited;
    uint256 public maxHoldingAmount;
    uint256 public minHoldingAmount;
    address public sushiSwapPair;
    mapping(address => bool) public blacklists;

    // Arbitrum SushiSwap router address
    address public constant sushiSwapRouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    uint256 _totalSupply = 690420000 * 1e18;

    constructor() ERC20("Elon's Ladies", "ELADY") {
        _mint(msg.sender, _totalSupply);
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function setRule(bool _limited, address _sushiSwapPair, uint256 _maxHoldingAmount, uint256 _minHoldingAmount) external onlyOwner {
        limited = _limited;
        sushiSwapPair = _sushiSwapPair;
        maxHoldingAmount = _maxHoldingAmount;
        minHoldingAmount = _minHoldingAmount;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) override internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");

        if (sushiSwapPair == address(0)) {
            require(from == owner() || to == owner(), "trading is not started");
            return;
        }

        if (limited && from == sushiSwapPair) {
            require(super.balanceOf(to) + amount <= maxHoldingAmount && super.balanceOf(to) + amount >= minHoldingAmount, "Forbid");
        }
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}
