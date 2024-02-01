// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3SwapCallback.sol";
import "./Pausable.sol";
import "./Ownable.sol";

error ZeroAddress();
error UnauthorizedPool();
error TransactionTooOld();
error InvalidSqrtX96Price();
error InvalidAmountIn();
error TooSmallProfit();
error ExceedLimitPrice();
error NegativeUsdPriceValue();

contract SmartTradeUniV3 is IUniswapV3SwapCallback, Pausable, Ownable {
    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    uint160 private constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    address private constant UNISWAP_FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    event SwapInfo(int256, int256, uint256);

    modifier NoDelegateCall() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _ ;
    }
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function isValidPool(address poolAddress) private view returns (bool){
        if (poolAddress == address(0)) {
            return false;
        }

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        IUniswapV3Factory poolFactory = IUniswapV3Factory(UNISWAP_FACTORY_ADDRESS);

        address token0 = pool.token0();
        if (token0 == address(0)) {
            return false;
        }

        address token1 = pool.token1();
        if (token1 == address(0)) {
            return false;
        }

        uint24 fee = pool.fee();
        if (fee != 3000 && fee != 500 && fee != 10000) {
            return false;
        }
        
        address realPool = poolFactory.getPool(token0, token1, fee);
        if (realPool == address(0)) {
            return false;
        }

        return realPool == poolAddress;
    }

    function masterSwap(
        address poolAddress,
        bool zeroForOne,
        int256 amountIn,
        uint160 sqrtPriceLimitX96,
        uint256 blockHeightRequired,
        int256 priceToken0Usd,
        int256 priceToken1Usd,
        int256 weiPriceUsd,
        int256 bribePercent,
        uint256 gas,
        int256 profitKoef
    ) external payable NoDelegateCall whenNotPaused returns (int256, int256, uint256) {
        if(poolAddress ==address(0)){
            revert ZeroAddress();
        }

        if (priceToken0Usd < 0 || priceToken1Usd < 0 || weiPriceUsd < 0 || bribePercent < 0) {
            revert NegativeUsdPriceValue();
        }

        if (block.number > blockHeightRequired) {
            revert TransactionTooOld();
        }

        if (amountIn <= 0) {
            revert InvalidAmountIn();
        }

        if (sqrtPriceLimitX96 <= MIN_SQRT_RATIO || sqrtPriceLimitX96 >= MAX_SQRT_RATIO) {
            revert InvalidSqrtX96Price();
        }

        if (!isValidPool(poolAddress)) {
            revert UnauthorizedPool();
        }

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (uint160 currentSqrtX96Price, , , , , , ) = pool.slot0();
        if ((zeroForOne && currentSqrtX96Price < sqrtPriceLimitX96) || (!zeroForOne && currentSqrtX96Price > sqrtPriceLimitX96)) {
            revert ExceedLimitPrice();
        }

        (int256 amount0, int256 amount1) = pool.swap(msg.sender,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96,
            abi.encode(msg.sender, zeroForOne)
        );

        int256 profitUsd = zeroForOne ? (-1 * amount1 * priceToken1Usd) - (amount0 * priceToken0Usd) :  (-1 * amount0 * priceToken0Usd) - (amount1 * priceToken1Usd);
        if (profitUsd < 0)
        {
            revert TooSmallProfit(); 
        }

        profitUsd = profitUsd * profitKoef;

        int256 gasCostUsd = int256(gas * tx.gasprice) * weiPriceUsd;
        profitUsd = profitUsd - gasCostUsd;
        if (profitUsd < 0)
        {
            revert TooSmallProfit(); 
        }

        uint256 bribe = 0;
        if (bribePercent > 0 && msg.value > 0) {
            int256 profitWei = profitUsd / weiPriceUsd;
            bribe = uint256(profitWei * bribePercent / 100);

            if (bribe > msg.value)
            {
                bribe = msg.value;
            }

            block.coinbase.transfer(bribe);

            uint256 bribeModWei = msg.value - bribe;
            if (bribeModWei > 0)
            {
                payable(msg.sender).transfer(bribeModWei);
            }
        }

        emit SwapInfo(amount0, amount1, bribe);
        return (amount0, amount1, bribe);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external whenNotPaused override {
        if(!isValidPool(msg.sender)){
            revert UnauthorizedPool();
        }

        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);

        (address payer, bool zeroForOne) = abi.decode(data, (address, bool));
                if(payer == address(0)){
            revert ZeroAddress();
        }

        if(zeroForOne) {
            IERC20(pool.token0()).transferFrom(payer, msg.sender, uint256(amount0Delta));
        }
        else {
            IERC20(pool.token1()).transferFrom(payer, msg.sender, uint256(amount1Delta));
        }
    }

    fallback() external payable{
        revert();
    }

    receive() external payable {
        revert();
    }
}
