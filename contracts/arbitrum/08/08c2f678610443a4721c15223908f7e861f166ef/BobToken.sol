// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);
}

contract BOBToken is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public marketingAddress;

    uint256 private fixedFee = 5;
    uint256 private decrementFee = 35;
    uint256 private lastFeeDecreaseTime;
    uint256 private feeDecreaseInterval = 2 minutes;

    uint256 public _maxTxAmount;
    uint256 public _maxWalletAmount;

    mapping(address => bool) public excludeFee;

    bool public tradingOpen = false;

    event RawTransfer(uint256 indexed amount, address indexed sender);

    constructor() ERC20("BobArb", "BOB") {
        uint256 _totalSupply = 100_000_000_000 * 10 ** 18; // 100 billion tokens with 18 decimals
        _maxTxAmount = 2 * (_totalSupply / 100);
        _maxWalletAmount = 100 * (_totalSupply / 100);
        _mint(msg.sender, _totalSupply);
        marketingAddress = _msgSender();
        lastFeeDecreaseTime = block.timestamp;
    }

    function init() public onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0xc873fEcbd354f5A56E00E710B90EF4201db2448d
        );
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        emit RawTransfer(amount, sender);

        if (recipient != owner() && recipient != uniswapV2Pair) {
            require(
                balanceOf(recipient).add(amount) <= _maxWalletAmount,
                "Recipient wallet limit exceeded"
            );
        }

        if (sender != owner() && recipient != uniswapV2Pair) {
            require(
                amount <= _maxTxAmount,
                "Transaction amount limit exceeded"
            );
        }

        if (sender == uniswapV2Pair || recipient == uniswapV2Pair) {
            if (sender != owner()) {
                require(tradingOpen, "Trading is not enabled");
            }
        }

        if (
            tradingOpen &&
            !excludeFee[sender] &&
            (sender == uniswapV2Pair || recipient == uniswapV2Pair)
        ) {
            uint256 currentFee = getCurrentFee();
            uint256 feeAmount = amount.mul(currentFee).div(100);
            uint256 remainingAmount = amount.sub(feeAmount);

            super._transfer(sender, marketingAddress, feeAmount);
            super._transfer(sender, recipient, remainingAmount);
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    function getCurrentFee() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp.sub(lastFeeDecreaseTime);
        uint256 decreaseCount = timeElapsed.div(feeDecreaseInterval).mul(5);

        uint256 currentFee = decrementFee.sub(decreaseCount);
        if (currentFee < fixedFee) {
            currentFee = fixedFee;
        }

        return currentFee;
    }

    function setFixedFee(uint256 _fixedFee) external onlyOwner {
        fixedFee = _fixedFee;
    }

    function setMarketingAddress(address _marketingAddress) external onlyOwner {
        marketingAddress = _marketingAddress;
    }

    function setMaxTxAmount(uint256 _newMaxTxAmount) external onlyOwner {
        _maxTxAmount = _newMaxTxAmount;
    }

    function setMaxWalletAmount(
        uint256 _newMaxWalletAmount
    ) external onlyOwner {
        _maxWalletAmount = _newMaxWalletAmount;
    }

    function setExcludeFee(address _address, bool _exclude) external onlyOwner {
        excludeFee[_address] = _exclude;
    }

    function setTradingOpen(bool _tradingOpen) external onlyOwner {
        tradingOpen = _tradingOpen;
    }

    function setTradingOpenAndLastFeeDecreaseTime() public onlyOwner {
        tradingOpen = true;
        lastFeeDecreaseTime = block.timestamp;
    }

    function updateFeeDecreaseInterval(
        uint256 _newInterval
    ) external onlyOwner {
        feeDecreaseInterval = _newInterval;
    }
}

