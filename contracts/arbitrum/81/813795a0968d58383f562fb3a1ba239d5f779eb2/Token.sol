/*

###########################################
## Token generated with ❤️ on 20lab.app ##
##########################################

*/

// SPDX-License-Identifier: No License

pragma solidity 0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Router02.sol";

contract ARB_TURBO is ERC20, ERC20Burnable, Ownable, Pausable {
    
    uint256 public swapThreshold;
    
    uint256 private _arbturboPending;

    address public arbturboAddress;
    uint16[3] public arbturboFees;

    mapping (address => bool) public isExcludedFromFees;

    uint16[3] public totalFees;
    bool private _swapping;

    IUniswapV2Router02 public routerV2;
    address public pairV2;
    mapping (address => bool) public AMMPairs;
 
    event SwapThresholdUpdated(uint256 swapThreshold);

    event arbturboAddressUpdated(address arbturboAddress);
    event arbturboFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event arbturboFeeSent(address recipient, uint256 amount);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event RouterV2Updated(address indexed routerV2);
    event AMMPairsUpdated(address indexed AMMPair, bool isPair);
 
    constructor()
        ERC20("ARB TURBO", "ATRO") 
    {
        address supplyRecipient = 0xb2CaAE29A84CD755b4c3c07B4cF93ecA87945bA6;
        
        updateSwapThreshold(35000000 * (10 ** decimals()));

        arbturboAddressSetup(0x8B9f4982526E1EdC46e5e34998FC8d0e0Fb27D03);
        arbturboFeesSetup(200, 0, 0);

        excludeFromFees(supplyRecipient, true);
        excludeFromFees(address(this), true); 

        _updateRouterV2(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

        _mint(supplyRecipient, 70000000000 * (10 ** decimals()));
        _transferOwnership(0xb2CaAE29A84CD755b4c3c07B4cF93ecA87945bA6);
    }

    receive() external payable {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _swapTokensForCoin(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerV2.WETH();

        _approve(address(this), address(routerV2), tokenAmount);

        routerV2.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function updateSwapThreshold(uint256 _swapThreshold) public onlyOwner {
        swapThreshold = _swapThreshold;
        
        emit SwapThresholdUpdated(_swapThreshold);
    }

    function arbturboAddressSetup(address _newAddress) public onlyOwner {
        arbturboAddress = _newAddress;

        excludeFromFees(_newAddress, true);

        emit arbturboAddressUpdated(_newAddress);
    }

    function arbturboFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        arbturboFees = [_buyFee, _sellFee, _transferFee];

        totalFees[0] = 0 + arbturboFees[0];
        totalFees[1] = 0 + arbturboFees[1];
        totalFees[2] = 0 + arbturboFees[2];
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        emit arbturboFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function excludeFromFees(address account, bool isExcluded) public onlyOwner {
        isExcludedFromFees[account] = isExcluded;
        
        emit ExcludeFromFees(account, isExcluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        
        bool canSwap = 0 + _arbturboPending >= swapThreshold;
        
        if (!_swapping && !AMMPairs[from] && canSwap) {
            _swapping = true;
            
            if (false || _arbturboPending > 0) {
                uint256 token2Swap = 0 + _arbturboPending;
                bool success = false;

                _swapTokensForCoin(token2Swap);
                uint256 coinsReceived = address(this).balance;
                
                uint256 arbturboPortion = coinsReceived * _arbturboPending / token2Swap;
                if (arbturboPortion > 0) {
                    (success,) = payable(address(arbturboAddress)).call{value: arbturboPortion}("");
                    require(success, "TaxesDefaultRouterWalletCoin: Fee transfer error");
                    emit arbturboFeeSent(arbturboAddress, arbturboPortion);
                }
                _arbturboPending = 0;

            }

            _swapping = false;
        }

        if (!_swapping && amount > 0 && to != address(routerV2) && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            uint256 fees = 0;
            uint8 txType = 3;
            
            if (AMMPairs[from]) {
                if (totalFees[0] > 0) txType = 0;
            }
            else if (AMMPairs[to]) {
                if (totalFees[1] > 0) txType = 1;
            }
            else if (totalFees[2] > 0) txType = 2;
            
            if (txType < 3) {
                
                fees = amount * totalFees[txType] / 10000;
                amount -= fees;
                
                _arbturboPending += fees * arbturboFees[txType] / totalFees[txType];

                
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
        }
        
        super._transfer(from, to, amount);
        
    }

    function _updateRouterV2(address router) private {
        routerV2 = IUniswapV2Router02(router);
        pairV2 = IUniswapV2Factory(routerV2.factory()).createPair(address(this), routerV2.WETH());
        
        _setAMMPair(pairV2, true);

        emit RouterV2Updated(router);
    }

    function setAMMPair(address pair, bool isPair) public onlyOwner {
        require(pair != pairV2, "DefaultRouter: Cannot remove initial pair from list");

        _setAMMPair(pair, isPair);
    }

    function _setAMMPair(address pair, bool isPair) private {
        AMMPairs[pair] = isPair;

        if (isPair) { 
        }

        emit AMMPairsUpdated(pair, isPair);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._afterTokenTransfer(from, to, amount);
    }
}

