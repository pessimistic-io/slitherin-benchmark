// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";

contract MemeBuff is ERC20, Ownable {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    uint256 immutable sellFeeMax = 5000;
    uint256 immutable buyBonusMax = 9000;
    uint256 public feeDenominator = 10000;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;
    bool private initialized;

    mapping(address => bool) public isFeeExempt;

    EnumerableSet.AddressSet private _pairs;

    event ReceivedBuyBonus(uint256 buyAmount, uint256 bonusAmount);

    constructor() ERC20("MemeBuff", "BUFF") {
        uint256 _totalSupply = 2_100_000_000_000_000 * 1e18;

        isFeeExempt[_msgSender()] = true;
        isFeeExempt[address(this)] = true;
        
        _mint(msg.sender, _totalSupply.div(2));
        _mint(address(this), _totalSupply.div(2));
        
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _buffTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _buffTransfer(sender, recipient, amount);
    }

    function _buffTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {

        uint256 feeAmount = 0;

        // if sender is LP pair, send rewards to recipient
        if (isPair(sender)) {
   
            uint256 bonusRate = getBuyBonus();

            if (launched() && bonusRate > 0) {
                uint256 bonusAmount = (amount * bonusRate) / feeDenominator;

                if (availableBonus() > bonusAmount) {
                    _transfer(address(this), recipient, bonusAmount);
                    emit ReceivedBuyBonus(amount, bonusAmount);
                }
            }

        } else if (isPair(recipient)) {
            uint256 sellFee = getSellFee();
            
            if (launched() && sellFee > 0) {

                feeAmount = (amount * getSellFee()) / feeDenominator;
                _transfer(sender, DEAD, feeAmount);
                
            }
        }

        _transfer(sender, recipient, amount - feeAmount);

        return true;
    }

    // returns the current sell fee. See fees start at maxSellFee and decay to 0 with rate of 5% per 24 hours
    function getSellFee() public view returns (uint256) {
        if (!launched()) {
            return 0;
        }
        uint256 timeSinceLaunch = block.timestamp - launchedAtTimestamp;
        uint256 fee = 0;

        if (timeSinceLaunch < 864000) {
            fee = sellFeeMax - ((timeSinceLaunch * sellFeeMax) / 864000);
        }
        
        return fee;
    }

    function getCurrTime() public view returns (uint256) {
        return block.timestamp;
    }

    // returns the current buy bonus amount. buy bonus start at maxBuyBonus and decrease to 0 with rate of 10% per 24 hours
    function getBuyBonus() public view returns (uint256) {
        if (!launched()) {
            return 0;
        }
        uint256 timeSinceLaunch = block.timestamp - launchedAtTimestamp;
        uint256 bonus = 0;

        if (timeSinceLaunch < 778500) {
            bonus = buyBonusMax - ((timeSinceLaunch * buyBonusMax) / 778500);
        }

        return bonus;
        
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function availableBonus() public view returns (uint256) {
        return balanceOf(address(this));
    }


    // burn all bonus tokens after bonus period is over
    function BurnBonusTokens() external onlyOwner {
        if (launched() && getBuyBonus() == 0) {
            uint256 amount = availableBonus();
            if (amount > 0) {
                _transfer(address(this), DEAD, amount);
            }
        }
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(this), "Cannot withdraw BUFF tokens");
        IERC20(tokenAddress).safeTransfer(msg.sender,IERC20(tokenAddress).balanceOf(address(this)));
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'MEMEBUFF: ETH_TRANSFER_FAILED');
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

     /*** ADMIN FUNCTIONS ***/
    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function isPair(address account) public view returns (bool) {
        return _pairs.contains(account);
    }

    function addPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "MEMEBUFF: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "MEMEBUFF: pair is the zero address");
        return _pairs.remove(pair);
    }

     function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "MEMEBUFF: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}
