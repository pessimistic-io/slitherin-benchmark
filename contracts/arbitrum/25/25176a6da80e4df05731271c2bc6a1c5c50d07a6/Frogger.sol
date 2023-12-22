// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract Frogger is Ownable, ERC20 {

    bool public limited;
    uint256 public maxHoldingAmount;
    uint256 public minHoldingAmount;
    address public uniswapV2Pair;

    struct WalletInfo {
        bool naughty;
        uint256 startBlock;
        uint256 hops;
        bool invincible;
    }

    mapping(address => WalletInfo) private walletData;

    constructor() ERC20("Frogger", "FROGGER") {
        _mint(msg.sender, 1000000 * 10**decimals());
        walletData[msg.sender].invincible = true;
        walletData[address(this)].invincible = true;
    }

    // shame
    function setNaughty(address _address, bool _status) external onlyOwner {
        walletData[_address].naughty = _status;
    }

    // star power
    function setInvincible(address _address, bool _status) external onlyOwner {
        walletData[_address].invincible = _status;
    }

    // important
    function setRule(bool _limited, address _uniswapV2Pair, uint256 _maxHoldingAmount, uint256 _minHoldingAmount) external onlyOwner {
        limited = _limited;
        uniswapV2Pair = _uniswapV2Pair;
        maxHoldingAmount = _maxHoldingAmount;
        minHoldingAmount = _minHoldingAmount;

        // uniswapV2 is invincible!
        walletData[_uniswapV2Pair].invincible = true;
    }

    // think ahead
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {

        require(!walletData[from].naughty && !walletData[to].naughty, "Naughty");

        if (uniswapV2Pair == address(0)) {
            require(from == owner() || to == owner(), "Trading disabled");
            return;
        }

        if (limited && from == uniswapV2Pair) {
            require(balanceOf(to) + amount <= maxHoldingAmount && balanceOf(to) + amount >= minHoldingAmount, "Forbid");
        }

        if (walletData[to].startBlock == 0) {
            walletData[to].startBlock = block.number;
            walletData[to].hops = 5;
        }
    }

    // Hop hop hop
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 currentHop = walletData[msg.sender].hops;
        bool recipientHasFirst = walletData[recipient].startBlock != 0;
        require(block.number <= walletData[msg.sender].startBlock + (currentHop * 6000) || walletData[msg.sender].invincible, "Truck squished the frog");
        require(currentHop > 0 || walletData[msg.sender].invincible, "No more hops");
        if (currentHop > 0 && !walletData[msg.sender].invincible) {
            walletData[msg.sender].hops -= 1;
            walletData[msg.sender].startBlock = block.number;
        }
        if (!recipientHasFirst) {
            walletData[recipient].startBlock = block.number;
            walletData[recipient].hops = 5;
        }

        return super.transfer(recipient, amount);
    }

    // Hop hop hop
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        uint256 currentHop = walletData[sender].hops;
        bool recipientHasFirst = walletData[recipient].startBlock != 0;
        require(block.number <= walletData[sender].startBlock + (currentHop * 6000) || walletData[sender].invincible, "Truck squished the frog");
        require(currentHop > 0 || walletData[sender].invincible, "No more hops");
        if (currentHop > 0 && !walletData[sender].invincible) {
            walletData[sender].hops -= 1;
            walletData[sender].startBlock = block.number;
        }
        if (!recipientHasFirst) {
            walletData[recipient].startBlock = block.number;
            walletData[recipient].hops = 5;
        }

        return super.transferFrom(sender, recipient, amount);
    }

    // Did someone call an ambulance?
    function revive(address squishedFrog) external {
        uint256 amount = (balanceOf(squishedFrog) / 2);
        require(balanceOf(msg.sender) >= 25 * 10**(decimals() - 2), "Not enough FROGGER to revive");
        require(walletData[squishedFrog].startBlock + walletData[squishedFrog].hops * 6000 < block.number, "Not squished");
        _burn(squishedFrog, amount);
        _transfer(squishedFrog, msg.sender, amount);

        delete walletData[squishedFrog].hops;
        delete walletData[squishedFrog].startBlock;
    }

    function findFrog(address wallet) public view returns (
        uint256 hops,
        uint256 totalFROGGER,
        bool invincibleStatus,
        uint256 squishBlock,
        uint256 currentBlock,
        uint256 startBlock
    ) {
        hops = walletData[wallet].hops;
        totalFROGGER = balanceOf(wallet);
        invincibleStatus = walletData[wallet].invincible;
        if (walletData[wallet].invincible || walletData[wallet].startBlock == 0) {
            squishBlock = 0;
        } else {
            squishBlock = walletData[wallet].startBlock + walletData[wallet].hops * 6000;
        }
        currentBlock = block.number;
        startBlock = walletData[wallet].startBlock;
    }
}


