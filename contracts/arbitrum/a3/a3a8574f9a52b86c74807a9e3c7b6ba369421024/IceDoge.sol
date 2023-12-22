// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";
import { EnumerableSet } from "./EnumerableSet.sol";
import { ICamelotRouter } from "./ICamelotRouter.sol";
import { ITaxSlotForTokens, ITaxSlotForWeth, ITaxSlotSellDecision, SwapKind } from "./ITaxSlot.sol";
import { ICamelotFactory } from "./ICamelotFactory.sol";


struct Slot {
    uint16 taxPercent;
    address destination;
}


// Camelot does not allow swap directly to the contract address of the token
// So that's why we need this proxy
contract ProxyHolder is Ownable {
    function withdraw(
        address _token
    ) public onlyOwner {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, _balance);
    }
}


contract IceDoge is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint16 public constant PERCENT_DENOMINATOR = 10000;

    IERC20 public immutable WETH;
    ICamelotRouter public immutable DEX_SWAP_ROUTER;
    ICamelotFactory public immutable DEX_FACTORY;

    ProxyHolder public PROXY_HOLDER;

    Slot[10] public slots;
    bool public shouldTakeTax;
    EnumerableSet.AddressSet private pairs;

    bool public initilized;
    bool public taxDisabledTemporary;

    constructor(
        IERC20 _weth,
        ICamelotRouter _dexSwapRouter,
        ICamelotFactory _dexFactory
    ) ERC20("Ice Doge Token", "ICEDOGE") {
        WETH = _weth;
        DEX_SWAP_ROUTER = _dexSwapRouter;
        DEX_FACTORY = _dexFactory;

        _mint(_msgSender(), 10 * 1e12 * decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _taxTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _taxTransfer(sender, recipient, amount);
    }

    function _taxTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (
            taxDisabledTemporary || !shouldTakeTax
        ) {
            _transfer(sender, recipient, amount);
        }

        address _actor;
        SwapKind _swapKind;
        if (pairs.contains(sender)) {
            _actor = recipient;
            _swapKind = SwapKind.SELL;
        } else {
            _actor = sender;
            _swapKind = SwapKind.BUY;
        }

        uint16 _totalTax = totalTaxToSell() + totalTaxWithoutSelling();
        uint256 _taxAmount = _totalTax * amount / PERCENT_DENOMINATOR;
        uint256 _transferAmount = amount - _taxAmount;

        _transfer(sender, recipient, _transferAmount);
        _transfer(sender, address(this), _taxAmount);
        _distributeTax(_actor, _swapKind);
        return true;
    }

    function _distributeTax(address _actor, SwapKind _swapKind) internal {
        taxDisabledTemporary = true;

        address[] memory _swapPath = new address[](2);
        _swapPath[0] = address(this);
        _swapPath[1] = address(WETH);

        uint256 _tokenBalanceBefore = balanceOf(address(this));
        uint256 _totalTaxToSell = totalTaxToSell();
        uint256 _totalTaxWithoutSelling = totalTaxWithoutSelling();

        uint256 _tokensToSell = balanceOf(address(this)) * _totalTaxToSell / PERCENT_DENOMINATOR;
        _approve(address(this), address(DEX_SWAP_ROUTER), _tokensToSell);
        DEX_SWAP_ROUTER
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _tokensToSell,
                0,
                _swapPath,
                address(PROXY_HOLDER),
                address(0),
                block.timestamp
            );
        PROXY_HOLDER.withdraw(address(WETH));

        uint256 _wethBalance = WETH.balanceOf(address(this));
        uint256 _tokenBalance = balanceOf(address(this));

        for (uint i = 0; i < slots.length; i++) {
            if (slots[i].taxPercent != 0 && slots[i].destination != address(0)) {
                bool _sellToWethDecision = ITaxSlotSellDecision(slots[i].destination).shouldSellTaxTokensToWeth();
                if (_sellToWethDecision && _totalTaxWithoutSelling != 0) {
                    uint256 _tokenAmount = (
                        slots[i].taxPercent
                        * 1e18
                        / _totalTaxToSell
                        * _tokenBalance
                        / 1e18
                    );
                    approve(address(slots[i].destination), _tokenAmount);
                    ITaxSlotForTokens(slots[i].destination).receiveTaxInTokens(
                        _actor,
                        _tokenAmount,
                        _swapKind
                    );
                } else if (
                    _sellToWethDecision && _totalTaxToSell != 0
                ) {
                    uint256 _tokenAmount = (
                        slots[i].taxPercent
                        * 1e18
                        / _totalTaxToSell
                        * (_tokenBalanceBefore - _tokenBalance)
                        / 1e18
                    );
                    uint256 _wethAmount = (
                        slots[i].taxPercent
                        * 1e18
                        / _totalTaxToSell
                        * _wethBalance
                        / 1e18
                    );
                    WETH.approve(
                        address(slots[i].destination),
                        _wethAmount
                    );
                    ITaxSlotForWeth(slots[i].destination).receiveTaxInWeth(
                        _actor,
                        _tokenAmount,
                        _wethAmount,
                        _swapKind
                    );
                }
            }
        }

        uint256 _remainWethBalance = WETH.balanceOf(address(this));
        uint256 _remainTokenBalance = balanceOf(address(this));
        if (_remainWethBalance > 0) {
            WETH.transfer(_actor, _remainWethBalance);
        }
        if (_remainTokenBalance > 0) {
            _transfer(address(this), _actor, _remainTokenBalance);
        }
        taxDisabledTemporary = false;
    }

    function totalTaxToSell() public view returns (uint16) {
        uint16 _totalTax;
        for (uint i = 0; i < slots.length; i++) {
            bool _sellToWethDecision = ITaxSlotSellDecision(slots[i].destination).shouldSellTaxTokensToWeth();
            if (_sellToWethDecision) {
                _totalTax += slots[i].taxPercent;
            }
        }
        return _totalTax;
    }

    function totalTaxWithoutSelling() public view returns (uint16) {
        uint16 _totalTax;
        for (uint i = 0; i < slots.length; i++) {
            bool _sellToWethDecision = ITaxSlotSellDecision(slots[i].destination).shouldSellTaxTokensToWeth();
            if (!_sellToWethDecision) {
                _totalTax += slots[i].taxPercent;
            }
        }
        return _totalTax;
    }

    function isPair(address _pair) public view returns (bool) {
        return pairs.contains(_pair);
    }


    // -- Authorized
    function initilize() public onlyOwner {
        require(!initilized, "Contract is already initlized");
        address _toEthPair = DEX_FACTORY.createPair(
            address(WETH), address(this)
        );
        pairs.add(_toEthPair);
        PROXY_HOLDER = new ProxyHolder();
        initilized = true;
    }

    function removePair(address _pair) public onlyOwner {
        pairs.remove(_pair);
    }

    function addPair(address _pair) public onlyOwner {
        pairs.add(_pair);
    }

    function switchTaxMode() public onlyOwner {
        shouldTakeTax = !shouldTakeTax;
    }

    function updateSlot(uint _index, Slot memory _newSlot) public onlyOwner {
        // TODO: require tax <= than 10%
        require(_index < 10, "Only 10 slots are available");
        uint16 _totalTax = totalTaxWithoutSelling() + totalTaxToSell();
        require(_totalTax - slots[_index].taxPercent + _newSlot.taxPercent <= 1000, "Total tax cannot be more than 10%");
        slots[_index] = _newSlot;
    }

    receive() external payable {}
}

