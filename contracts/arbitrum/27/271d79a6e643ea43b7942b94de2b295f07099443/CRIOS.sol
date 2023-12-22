// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./IPair.sol";
import "./OwnerRecovery.sol";
import "./LiquidityPoolManagerImplementationPointer.sol";
import "./WalletObserverImplementationPointer.sol";

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

////// src/IUniswapV2Pair.sol
/* pragma solidity 0.8.10; */
/* pragma experimental ABIEncoderV2; */

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint) external;
}



contract CRIOS is
    ERC20,
    ERC20Burnable,
    Ownable,
    OwnerRecovery,
    LiquidityPoolManagerImplementationPointer,
    WalletObserverImplementationPointer
{
    address public immutable criosManager;
    address private devWallet;
    address private liquidity;
    address public treasury;
    uint256 public sellFeesAmount;
    uint256 public buyFeesAmount;
    uint256 public isWithin24Hours;
    mapping (address => bool) public excludedFromFees;

 

    /// @notice WETH address
    address public immutable WETH;
    /// @notice Address of UniswapV2Router
    IUniswapV2Router02 public immutable uniswapV2Router;
    /// @notice Address of QPN/ETH LP
    address public immutable uniswapV2Pair;

    /// @notice Bool if swap is enabled
    bool public swapEnabled = false;
    /// @notice Bool if limits are in effect
    bool public limitsInEffect = true;

    /// @notice Current max wallet amount (If limits in effect)
    uint256 public maxWallet;
    /// @notice Current max transaction amount (If limits in effect)
    uint256 public maxTransactionAmount;

   /// @notice Bool if address is AMM pair
    mapping(address => bool) public automatedMarketMakerPairs;


    modifier onlyCriosManager() {
        address sender = _msgSender();
        require(
            sender == address(criosManager),
            "Implementations: Not criosManager"
        );
        _;
    }



    /// @notice You can use this contract for only the most basic simulation
    /// @param _criosManager is the node Manager contract
    /// @param _treasury is the multisig address treasury 
    constructor(address _criosManager, address _treasury, address _devWallet, address _liquidityWallet, address _weth) ERC20("CRIOS", "CRIOS") {
        require(
            _criosManager != address(0),
            "Implementations: criosManager is not set"
        );
        criosManager = _criosManager;

        WETH = _weth;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x16e71B13fE6079B4312063F7E81F76d165Ad32Ad  // ZyberSwap
        );

         uniswapV2Router = _uniswapV2Router;

         uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);


        devWallet = _devWallet;
        treasury = _treasury;
        liquidity = _liquidityWallet;

        maxWallet = 840_000_000 * 1e18; // 2%
        maxTransactionAmount = 840_000_000 * 1e18; // 2%

        setSellFeesAmount(50); // 5% fees each sell | 2% to treasury | 2% to liquidity | 1% to devWallet
        setBuyFeesAmount(50); // 5% fees each buy  | 2% to treasury | 2% to liquidity | 1% to devWallet

        // setFeesExcluded(owner(), true);
        // setFeesExcluded(address(this), true);


        // excludeFromMaxTransaction(owner(), true);
        // excludeFromMaxTransaction(address(this), true);


        isWithin24Hours = block.timestamp + 1 days;

        _mint(owner(), 42_000_000_000 * (10**18));
    }
    

    /// AMM PAIR ///
    /// @notice       Sets if address is AMM pair
    /// @param pair   Address of pair
    /// @param value  Bool if AMM pair
    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) public onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    /// @dev Internal function to set `vlaue` of `pair`
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

    }



    function enableTrading(bool _isTrue) external onlyOwner {
        swapEnabled = _isTrue;
    }



     function setSellFeesAmount(uint _sellFeesAmount) public onlyOwner {
        require(_sellFeesAmount <= 150, "fees too high");
        sellFeesAmount = _sellFeesAmount;
    }


    function setBuyFeesAmount(uint _buyFeesAmount) public onlyOwner {
        require(_buyFeesAmount <= 150, "fees too high");
        buyFeesAmount = _buyFeesAmount;
    }


    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }


    function setDevWallet(address _devWallet) public onlyOwner {
        devWallet = _devWallet;
    }


    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (address(walletObserver) != address(0)) {
            walletObserver.beforeTokenTransfer(_msgSender(), from, to, amount);
        }
    }


    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        if (address(liquidityPoolManager) != address(0)) {
            liquidityPoolManager.afterTokenTransfer(_msgSender());
        }
    }


    function accountBurn(address account, uint256 amount)
        external
        onlyCriosManager
    {
        // Note: _burn will call _beforeTokenTransfer which will ensure no denied addresses can create cargos
        // effectively protecting criosManager from suspicious addresses
        super._burn(account, amount);
    }


    function accountReward(address account, uint256 amount)
        external
        onlyCriosManager
    {
        super._mint(account, amount);
    }

    
    function liquidityReward(uint256 amount) external onlyCriosManager {
        require(
            address(liquidity) != address(0),
            "Crios: LiquidityPoolManager is not set"
        );
        super._mint(address(liquidity), amount);
    }



    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return _transferTaxOverride(_msgSender(), recipient, amount);
    }



    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transferTaxOverride(sender, recipient, amount);

        uint256 currentAllowance = allowance(sender,_msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }



    // exclude addresses from fees (for exemple to deposit the initial liquidity without fees)
    function setFeesExcluded(address _addr, bool _isExcluded) public onlyOwner {
        excludedFromFees[_addr] = _isExcluded;
    }



    function _transferTaxOverride(address sender, address recipient, uint256 amount) internal returns (bool) {

        uint256 _transferAmount = amount;
        
        if (!excludedFromFees[sender] && swapEnabled) {        // check if sender is excluded From fees
            uint additionalSellFees = 0;

           if (limitsInEffect) {
                if (
                    sender != owner() &&
                    recipient != owner() &&
                    recipient != address(0) &&
                    recipient != address(0xdead) 
                ) {
                        //when buy
                     if (
                    automatedMarketMakerPairs[sender] 
                     ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + balanceOf(recipient) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[recipient]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
           } 
                }
           }


        bool takeFee = !limitsInEffect;

         if(takeFee) {
            if (automatedMarketMakerPairs[recipient]) { // if the recipient address is a liquidity pool, apply sell fee
                uint _fees = (amount * sellFeesAmount) / 1000;

                if(block.timestamp >= isWithin24Hours ) { // if the sender address already sold in the last 24 hours, apply additional sell fee
                    additionalSellFees = (amount * 70) / 1000;
                }

                _fees += additionalSellFees;
                _transferAmount = amount - _fees;

                uint devWalletFees = (_fees * 20) / 100;
                uint treasuryFees = (_fees * 40) / 100;
                uint liquidityFees = _fees - devWalletFees - treasuryFees;

                _transfer(sender, treasury, treasuryFees ); // transfer fee to treasury address
                _transfer(sender, devWallet, devWalletFees  ); // transfer fee to devWallet address
                _transfer(sender, liquidity, liquidityFees ); // transfer fee to liquidity address
            }

            else if(automatedMarketMakerPairs[sender]) { // if the sender address is a liquidity pool, apply buy fee
                uint _fees = (amount * buyFeesAmount) / 1000;
                _transferAmount = amount - _fees;

                uint devWalletFees = (_fees * 20) / 100;
                uint treasuryFees = (_fees * 40) / 100;
                uint liquidityFees = _fees - devWalletFees - treasuryFees;

                _transfer(sender, treasury, treasuryFees); // transfer fee to treasury address
                _transfer(sender, devWallet, devWalletFees); // transfer fee to devWallet address
                _transfer(sender, liquidity, liquidityFees); // transfer fee to liquidity address
                 }

             } 
            _transfer(sender, recipient, _transferAmount);
          }
        
        
        return true;
    }
    
    
        /// @notice Remove limits in place
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }


    // retreive token from pool contract (with getter function)
    function getPoolToken(address pool, string memory signature, function() external view returns(address) getter) private returns (address token) {
        (bool success, ) = pool.call(abi.encodeWithSignature(signature)); // if the call succeed (pool address have the "signature" method or "pool" is an EOA)
        if (success) {
            if (Address.isContract(pool)) { // verify that the pool is a contract (constructor can bypass this but its not dangerous)
                return getter();
            }
        }
    }

    // return true if the "_recipient" address is a FEAR liquidity pool
    function isCRIOSLiquidityPool(address _recipient) private returns (bool) {
        address token0 = getPoolToken(_recipient, "token0()", IPair(_recipient).token0);
        address token1 = getPoolToken(_recipient, "token1()", IPair(_recipient).token1);

        return (token0 == address(this) || token1 == address(this));
    }

        function withdrawStuckToken(
        address _token,
        address _to
    ) external onlyOwner {
        require(_token != address(0), "_token address cannot be 0");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, _contractBalance);
    }


    /// @notice Withdraw stuck ETH from contract
    function withdrawStuckEth(address toAddr) external onlyOwner {
        (bool success, ) = toAddr.call{value: address(this).balance}("");
        require(success);
    }

    receive() external payable {}

}
