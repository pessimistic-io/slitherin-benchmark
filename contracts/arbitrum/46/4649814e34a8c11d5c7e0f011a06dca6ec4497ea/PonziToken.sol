// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

// import "forge-std/console.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";
import "./Math.sol";
import { ICamelotRouterV2 } from "./ICamelotRouterV2.sol";

import "./console.sol";

contract SixToken is ERC20Burnable, Ownable {
    struct ReferalLevels {
        address parentLevel1;
        address parentLevel2;
        address parentLevel3;
        address parentLevel4;
        address parentLevel5;
    }

    struct User {
        address referredBy;
        bool referred;
    }

    uint256 public constant FEE_DENOMINATOR = 10_000;

    /**
     * @dev commissionRate
     * + lvl1: 1%
     * + lvl2: 0.5%
     * + lvl3: 0.3%
     * + lvl4: 0.1%
     * + lvl5: 0.1%
     */
    uint256 public constant taxForParentLevel1Rate = 100;
    uint256 public constant taxForParentLevel2Rate = 50;
    uint256 public constant taxForParentLevel3Rate = 30;
    uint256 public constant taxForParentLevel4Rate = 10;
    uint256 public constant taxForParentLevel5Rate = 10;
    uint256 public constant maxTaxForParentsRate = 200;

    uint256 public constant taxRate = 600;
    uint256 public constant rebateRate = 200;
    uint256 public constant commissionRate = 200;
    uint256 public constant devFundRate = 100;
    uint256 public constant burnRate = 100;

    address payable public devFund;

    bool private _inSwapAndLiquify;
    bool public swapAndTreasureEnabled = true;
    uint256 public swapAtAmount;

    ICamelotRouterV2 public uniswapV2Router;
    address public uniswapV2Pair;

    bool public limited;
    uint256 public maxHoldingAmount;
    uint256 public minHoldingAmount;
    mapping(address account => bool isBlacklisted) public blacklists;

    mapping(address => ReferalLevels) public refersInfo;
    mapping(address => User) public usersInfo;

    modifier lockTheSwap() {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    /* ──────────────────────────CONSTRUCTOR──────────────────────────────────*/
    constructor(uint256 _totalSupply, address _devFund, address _router) ERC20("SIX Token", "SIX") {
        devFund = payable(_devFund);
        uniswapV2Router = ICamelotRouterV2(_router);

        _mint(msg.sender, _totalSupply);
        swapAtAmount = totalSupply() / 100_000; // 0.001%
    }

    function setParent(address parentAddress) public {
        require(usersInfo[msg.sender].referredBy == address(0), "Already being referred");
        require(usersInfo[msg.sender].referred == false, "Already referred");
        require(parentAddress != msg.sender, "You cannot refer yourself");
        usersInfo[msg.sender].referredBy = parentAddress;

        address parentLevel1 = usersInfo[msg.sender].referredBy;
        address parentLevel2 = usersInfo[parentLevel1].referredBy;
        address parentLevel3 = usersInfo[parentLevel2].referredBy;
        address parentLevel4 = usersInfo[parentLevel3].referredBy;
        address parentLevel5 = usersInfo[parentLevel4].referredBy;

        if ((parentLevel1 != msg.sender) && (parentLevel1 != address(0))) {
            refersInfo[msg.sender].parentLevel1 = parentLevel1;
            usersInfo[parentLevel1].referred = true;
        }
        if ((parentLevel2 != msg.sender) && (parentLevel2 != address(0))) {
            refersInfo[msg.sender].parentLevel2 = parentLevel2;
        }
        if ((parentLevel3 != msg.sender) && (parentLevel3 != address(0))) {
            refersInfo[msg.sender].parentLevel3 = parentLevel3;
        }
        if ((parentLevel4 != msg.sender) && (parentLevel4 != address(0))) {
            refersInfo[msg.sender].parentLevel4 = parentLevel4;
        }
        if ((parentLevel5 != msg.sender) && (parentLevel5 != address(0))) {
            refersInfo[msg.sender].parentLevel5 = parentLevel5;
        }
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _sixTransfer(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address sender, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        _sixTransfer(sender, to, amount);
        return true;
    }

    function takeTaxForParentsRate(address sender, address tokenSendFrom, uint256 amount) internal returns (uint256) {
        ReferalLevels memory referInfo = refersInfo[sender];
        address parent_level_1 = referInfo.parentLevel1;
        address parent_level_2 = referInfo.parentLevel2;
        address parent_level_3 = referInfo.parentLevel3;
        address parent_level_4 = referInfo.parentLevel4;
        address parent_level_5 = referInfo.parentLevel5;

        uint256 taxForParentLevel1Amt;
        uint256 taxForParentLevel2Amt;
        uint256 taxForParentLevel3Amt;
        uint256 taxForParentLevel4Amt;
        uint256 taxForParentLevel5Amt;
        uint256 taxForParentsRate;

        if (parent_level_1 != address(0)) {
            taxForParentsRate += taxForParentLevel1Rate;
            taxForParentLevel1Amt = parent_level_1 != address(0) ? getAmtFromRate(amount, taxForParentLevel1Rate) : 0;
        }
        if (parent_level_2 != address(0)) {
            taxForParentsRate += taxForParentLevel2Rate;
            taxForParentLevel2Amt = parent_level_2 != address(0) ? getAmtFromRate(amount, taxForParentLevel2Rate) : 0;
        }
        if (parent_level_3 != address(0)) {
            taxForParentsRate += taxForParentLevel3Rate;
            taxForParentLevel3Amt = parent_level_3 != address(0) ? getAmtFromRate(amount, taxForParentLevel3Rate) : 0;
        }
        if (parent_level_4 != address(0)) {
            taxForParentsRate += taxForParentLevel4Rate;
            taxForParentLevel4Amt = parent_level_4 != address(0) ? getAmtFromRate(amount, taxForParentLevel4Rate) : 0;
        }
        if (parent_level_5 != address(0)) {
            taxForParentsRate += taxForParentLevel5Rate;
            taxForParentLevel5Amt = parent_level_5 != address(0) ? getAmtFromRate(amount, taxForParentLevel5Rate) : 0;
        }

        if (taxForParentLevel1Amt > 0) {
            super._transfer(tokenSendFrom, parent_level_1, taxForParentLevel1Amt);
        }
        if (taxForParentLevel2Amt > 0) {
            super._transfer(tokenSendFrom, parent_level_2, taxForParentLevel2Amt);
        }
        if (taxForParentLevel3Amt > 0) {
            super._transfer(tokenSendFrom, parent_level_3, taxForParentLevel3Amt);
        }
        if (taxForParentLevel4Amt > 0) {
            super._transfer(tokenSendFrom, parent_level_4, taxForParentLevel4Amt);
        }
        if (taxForParentLevel5Amt > 0) {
            super._transfer(tokenSendFrom, parent_level_5, taxForParentLevel5Amt);
        }
        return taxForParentsRate;
    }

    function _sixTransfer(address from, address to, uint256 amount) internal {
        if (from == address(this) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
            super._transfer(from, to, amount);
            return;
        } else {
            address sender = from == uniswapV2Pair ? to : from;
            uint256 taxForParentsRate = takeTaxForParentsRate(sender, from, amount);
            uint256 _burnRate = taxRate - devFundRate - taxForParentsRate - rebateRate;

            /**
             *
             * @dev tax for estimating the latest amount, which send to `to`
             * Case 1: if `to` == uniswapV2Pair => uniswapV2Pair is always received (100% - 6%) * amount. B/c user will
             * sent less if have parent
             * Case 2: if `from` == uniswapV2Pair && user have no parent => user will be received (100% - 6%) * amount.
             * B/c 3% will be burned
             * Case 3: if `from` == uniswapV2Pair && user have parent => user will be received (100% - 4%) * amount
             *
             */
            uint256 _userTaxRate = taxRate;
            if (from == uniswapV2Pair && taxForParentsRate > 0) {
                _userTaxRate = devFundRate + burnRate + maxTaxForParentsRate;
            }

            if (taxForParentsRate == 0) {
                _burnRate += rebateRate;
            }

            if (to == uniswapV2Pair) {
                super._transfer(from, msg.sender, getAmtFromRate(amount, _burnRate));
            }

            super.burn(getAmtFromRate(amount, _burnRate));
            if (
                swapAndTreasureEnabled && balanceOf(address(this)) >= swapAtAmount && !_inSwapAndLiquify
                    && to == uniswapV2Pair
            ) {
                _swapAndSendTreasure(swapAtAmount);
            }
            super._transfer(from, to, amount - getAmtFromRate(amount, _userTaxRate));
            super._transfer(from, address(this), getAmtFromRate(amount, devFundRate));
        }
    }

    function getAmtFromRate(uint256 amount, uint256 rate) private pure returns (uint256) {
        return Math.mulDiv(amount * 1e24, rate, FEE_DENOMINATOR * 1e24);
    }

    /* ──────────────────────INTERNAL──────────────────────────────────────*/
    function _swapAndSendTreasure(uint256 _amount) internal lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), _amount);
        bool successSwapBack = false;

        (successSwapBack,) = address(uniswapV2Router).call(
            abi.encodeWithSignature(
                "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,address,uint256)",
                _amount,
                0,
                path,
                address(this),
                address(0),
                block.timestamp + 10
            )
        );

        if (!successSwapBack) {
            (successSwapBack,) = address(uniswapV2Router).call(
                abi.encodeWithSignature(
                    "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                    _amount,
                    0,
                    path,
                    address(this),
                    block.timestamp + 10
                )
            );
        }
        if (!successSwapBack) {
            return;
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success,) = devFund.call{ value: ethBalance }("");
            require(success, "ETH transfer failed");
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");
        if (uniswapV2Pair == address(0)) {
            require(from == owner() || to == owner(), "Trading is not started");
            return;
        }

        if (limited && from == uniswapV2Pair) {
            require(
                super.balanceOf(to) + amount <= maxHoldingAmount && super.balanceOf(to) + amount >= minHoldingAmount,
                "Forbid"
            );
            return;
        }
    }

    /* ───────────────────────OWNER ACCESS─────────────────────────────────────*/
    function setSwapAtAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "zero input");
        swapAtAmount = _amount;
    }

    function setDevFund(address _devFund) public onlyOwner {
        require(_devFund != address(0), "Invalid dev fund address");
        devFund = payable(_devFund);
    }

    function setSwapAndTreasureEnabled(bool _state) external onlyOwner {
        swapAndTreasureEnabled = _state;
    }

    function recover(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
            IERC20(_token).transfer(msg.sender, _amount);
        } else {
            (bool success,) = payable(msg.sender).call{ value: _amount }("");
            require(success, "Can't send ETH");
        }
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function setUniswapV2Pair(address _uniswapV2Pair) external onlyOwner {
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setRule(bool _limited, uint256 _maxHoldingAmount, uint256 _minHoldingAmount) external onlyOwner {
        limited = _limited;
        maxHoldingAmount = _maxHoldingAmount;
        minHoldingAmount = _minHoldingAmount;
    }

    /* ─────────────────────PERIPHERALS───────────────────────────────────────*/
    // to recieve ETH from uniswapV2Router when swapping
    receive() external payable { }
}

