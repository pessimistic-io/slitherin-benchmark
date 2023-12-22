// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC4626.sol";
import "./Owned.sol";
import "./FixedPointMathLib.sol";
import "./SafeTransferLib.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router.sol";
import "./IGmxVault.sol";
import "./IGmxRouter.sol";
import "./IGmxPositionRouter.sol";
import "./IGmxVaultPriceFeed.sol";
import "./IGmxPositionManager.sol";
import "./UniswapV2Library.sol";
import "./SafeMathUniswap.sol";



contract LogarithmVaultUniV2 is ERC4626, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SafeMathUniswap for uint256;
 
    
    address public immutable pool;
    address public immutable product;
    address public immutable swapRouter;
    address public immutable gmxVault;
    address public immutable gmxRouter;
    address public immutable gmxPositionRouter;
    address public immutable gmxVaultPriceFeed;
    address public immutable gmxPositionManager;

    mapping(address => bool) public keeper;
    mapping(address => bool) public whitelistedDepositor;

    uint16 internal immutable ASSET_DECIMALS;
    uint16 internal immutable PRODUCT_DECIMALS;
    uint16 internal immutable LP_DECIMALS;
    uint16 internal constant DECIMALS = 6;
    uint16 internal constant GMX_PRICE_PRECISION = 30;
    uint32 public rehedgeThreshold;
    uint32 public targetLeverage;
    uint32 public slippageTollerance;
    uint32 internal constant SIZE_DELTA_MULT = 998004; // 6 decimals
    uint48 internal executionFee = 200000000000000;

    uint256 public lastRebalanceTimestamp;
    uint256 public vaultActivationTimestamp;
    uint256 public depositedAssets;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyWhitelisted() {
        if (whitelistedDepositor[msg.sender]) {
            _;
        } else {
            revert("NOT_WHITELISTED");
        }
    }

    modifier onlyKeeper() {
        if(keeper[msg.sender] || msg.sender == owner || msg.sender == address(this)) {
            _;
        } else {
            revert("NOT_KEEPER");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _asset,
        address _product,
        address _pool,
        address _swapRouter,
        address _gmxVault,
        address _gmxRouter,
        address _gmxPositionRouter,
        address _gmxVaultPriceFeed,
        address _gmxPositionManager,
        uint256 _rehedgeThreshold,
        uint256 _targetLeverage,
        uint256 _slippageTollerance
    ) 
    ERC4626(ERC20(_asset), "Logarithm Vault UniV2 POC", "LV-poc")
    Owned(msg.sender) {
        product = _product;
        pool = _pool;
        swapRouter = _swapRouter;
        gmxVault = _gmxVault;
        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;
        gmxVaultPriceFeed = _gmxVaultPriceFeed;
        gmxPositionManager = _gmxPositionManager;
        rehedgeThreshold = uint32(_rehedgeThreshold);
        targetLeverage = uint32(_targetLeverage);
        slippageTollerance = uint32(_slippageTollerance);

        ASSET_DECIMALS = ERC20(_asset).decimals();
        PRODUCT_DECIMALS = ERC20(_product).decimals();
        LP_DECIMALS = ERC20(_pool).decimals();

        
        // approve margin trading on GMX
        IGmxRouter(_gmxRouter).approvePlugin(_gmxPositionRouter);

        
        // TODO: push approvals from constructor to function execution
        // approve asset to GMX
        ERC20(_asset).approve(_gmxRouter, type(uint256).max);

        // approve asset to swap router
        ERC20(_asset).approve(_swapRouter, type(uint256).max);

        // approve product to swap router 
        ERC20(_product).approve(_swapRouter, type(uint256).max);

        // approve pool tokens to swap router
        ERC20(_pool).approve(_swapRouter, type(uint256).max);

        vaultActivationTimestamp = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS LOGIC
    //////////////////////////////////////////////////////////////*/

    function addKeepers(address[] calldata _keepers) public onlyOwner {
        for (uint256 i = 0; i < _keepers.length; i++) {
            keeper[_keepers[i]] = true;
        }
    }

    function removeKeepers(address[] calldata _keepers) public onlyOwner {
        for (uint256 i = 0; i < _keepers.length; i++) {
            keeper[_keepers[i]] = false;
        }
    }
    
    function addWhitelistedDepositors(address[] calldata _depostiors) public onlyOwner {
        for (uint256 i = 0; i < _depostiors.length; i++) {
            whitelistedDepositor[_depostiors[i]] = true;
        }
    }

    function removeWitelistedDepositors(address[] calldata _depostiors) public onlyOwner {
        for (uint256 i = 0; i < _depostiors.length; i++) {
            whitelistedDepositor[_depostiors[i]] = false;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function setReheadgeThreshold( uint256 _rehedgeThreshold) public onlyOwner {
        rehedgeThreshold = uint32(_rehedgeThreshold);
    }
    
    function setTargetLeverage(uint256 _targetLeverage) public onlyOwner {
        targetLeverage = uint32(_targetLeverage);
    }

    function setSlippageTollerance(uint256 _slippageTollerance) public onlyOwner {
        slippageTollerance = uint32(_slippageTollerance);
    }

    function setExecutionFee(uint256 _executionFee) public onlyOwner {
        executionFee = uint48(_executionFee);
    }

    function sweepETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    function sweepERC(address token) external onlyOwner {
        ERC20(token).transfer(owner, ERC20(token).balanceOf(address(this)));
    }

    function resetDepositedAssets() external onlyOwner {
        depositedAssets = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public onlyWhitelisted override returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public onlyWhitelisted override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        uint256 assetBalanceBeforeWithdraw = asset.balanceOf(address(this));
        _removeLiquidity(assets);
        uint256 assetBalanceAfterWithdraw = asset.balanceOf(address(this));
        assets = assetBalanceAfterWithdraw - assetBalanceBeforeWithdraw;

        _burn(owner, shares);

        asset.safeTransfer(receiver, assets);

        if(rebalanceRequired()) {
            _rebalance();
        }

        uint256 sharesFraction = shares.mulDivDown(10 ** DECIMALS, totalSupply);
        depositedAssets = depositedAssets.mulDivDown(10 ** DECIMALS - sharesFraction, 10 ** DECIMALS);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            UNISWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(uint256 amount) public onlyKeeper {
        _addLiquidity(amount);
    }
    
    function _addLiquidity(uint256 amount) internal {

        // get optimal swap amount
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 assetReserve = uint256(address(asset) < product ? reserve0 : reserve1);
        uint256 swapAmount = getSwapAmountIn(amount, assetReserve);
        
        // swap half of asset to product
        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = product;
        IUniswapV2Router(swapRouter).swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        // add liquidity to pool

        IUniswapV2Router(swapRouter).addLiquidity(
            address(asset),
            product,
            ERC20(asset).balanceOf(address(this)),
            ERC20(product).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        
    }

    function removeLiquidity(uint256 amount) public onlyKeeper {
        _removeLiquidity(amount);
    }

    function _removeLiquidity(uint256 amount) internal {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 assetReserve = uint256(address(asset) < product ? reserve0 : reserve1);
        uint256 swapAmount = getSwapAmountIn(amount, assetReserve);
        uint256 lpTotalSupply = ERC20(pool).totalSupply();
        uint256 lpToWithdraw = (swapAmount * lpTotalSupply) / (assetReserve);

        // remove liquidity from pool
        IUniswapV2Router(swapRouter).removeLiquidity(
            address(asset),
            product,
            lpToWithdraw,
            0,
            0,
            address(this),
            block.timestamp
        );

        // swap product to asset
        address[] memory path = new address[](2);
        path[0] = product;
        path[1] = address(asset);
        IUniswapV2Router(swapRouter).swapExactTokensForTokens(
            ERC20(product).balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function exitLiquidity() public onlyKeeper {
        _exitLiquidity();
    }

    function _exitLiquidity() internal {
        // remove liquidity from pool
        uint256 lpBalance = ERC20(pool).balanceOf(address(this));
        IUniswapV2Router(swapRouter).removeLiquidity(
            address(asset),
            product,
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        // swap product to asset
        address[] memory path = new address[](2);
        path[0] = product;
        path[1] = address(asset);
        IUniswapV2Router(swapRouter).swapExactTokensForTokens(
            ERC20(product).balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function getLpAssetBalance() public view returns (uint256 assetBalance) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 assetReserve = uint256(address(asset) < product ? reserve0 : reserve1);
        uint256 lpTotalSupply = ERC20(pool).totalSupply();
        uint256 lpVaultBalance = ERC20(pool).balanceOf(address(this));
        assetBalance = lpVaultBalance.mulDivUp(assetReserve, lpTotalSupply);
    }

    function getLpExposure() public view returns (uint256 exposure) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 productReserve = uint256(product < address(asset) ? reserve0 : reserve1);
        uint256 lpTotalSupply = ERC20(pool).totalSupply();
        uint256 lpVaultBalance = ERC20(pool).balanceOf(address(this));
        exposure = lpVaultBalance.mulDivUp(productReserve, lpTotalSupply);
    }

    function getLpNetBalance() public view returns (uint256 lpValue) {
        if(ERC20(pool).balanceOf(address(this)) == 0) return 0;
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 assetReserve = uint256(address(asset) < product ? reserve0 : reserve1);
        uint256 productReserve = uint256(product < address(asset) ? reserve0 : reserve1);
        uint256 lpTotalSupply = ERC20(pool).totalSupply();
        uint256 lpVaultBalance = ERC20(pool).balanceOf(address(this));
        uint256 assetValue = lpVaultBalance.mulDivUp(assetReserve, lpTotalSupply);
        uint256 productAmount = lpVaultBalance.mulDivUp(productReserve, lpTotalSupply);
        uint256 productValue = UniswapV2Library.getAmountOut(productAmount, productReserve, assetReserve);
        lpValue = assetValue + productValue;
    }

    function getSwapAmountIn(uint256 amtA, uint256 resA) internal pure returns (uint256) {
        return (FixedPointMathLib.sqrt(resA * (3988009 * resA + 3988000 * amtA)) - (1997 * resA)) / 1994;
    }

    /*//////////////////////////////////////////////////////////////
                                GMX LOGIC
    //////////////////////////////////////////////////////////////*/

    function increaseHedge(uint256 amount) public onlyKeeper returns (bytes32 positionKey) {
        return _increaseHedge(amount);
    }
    
    function _increaseHedge(uint256 amount) internal returns (bytes32 positionKey) {
        address[] memory path = new address[](1);
        path[0] = address(asset);
        uint256 sizeDelta = (amount * uint256(targetLeverage) * uint256(SIZE_DELTA_MULT)).mulDivDown(10 ** GMX_PRICE_PRECISION, 10 ** (ASSET_DECIMALS + DECIMALS * 2));
        uint256 markPrice = IGmxVaultPriceFeed(gmxVaultPriceFeed).getPrice(product, false, false, false);
        uint256 acceptablePrice = markPrice.mulDivDown(10 ** DECIMALS - slippageTollerance, 10 ** DECIMALS);

        positionKey = IGmxPositionRouter(gmxPositionRouter).createIncreasePosition{ value: executionFee }(
            path,
            product,
            amount,
            0,
            sizeDelta,
            false,
            acceptablePrice,
            executionFee,
            bytes32(0),
            address(0)
        );
    }

    function decreaseHedge(uint256 amount) public onlyKeeper returns (bytes32 positionKey) {
        return _decreaseHedge(amount);
    }

    function _decreaseHedge(uint256 amount) internal returns (bytes32 positionKey) {
        address[] memory path = new address[](1);
        path[0] = address(asset);
        uint256 collateralDelta = amount.mulDivDown(10 ** GMX_PRICE_PRECISION, 10 ** ASSET_DECIMALS);
        uint256 sizeDelta = collateralDelta.mulDivDown(uint256(targetLeverage) * uint256(SIZE_DELTA_MULT), 10 ** DECIMALS * 10 ** DECIMALS);
        uint256 acceptablePrice = IGmxVaultPriceFeed(gmxVaultPriceFeed).getPrice(product, false, false, false).mulDivDown(10 ** DECIMALS + slippageTollerance, 10 ** DECIMALS);


        positionKey = IGmxPositionRouter(gmxPositionRouter).createDecreasePosition{ value: executionFee }(
            path,
            product,
            collateralDelta,
            sizeDelta,
            false,
            address(this),
            acceptablePrice,
            0,
            executionFee,
            false,
            address(0)
        );
    }

    function exitPosition() public onlyKeeper {
        _exitPosition();
    }

    function _exitPosition() internal {
        bytes32 key = IGmxVault(gmxVault).getPositionKey(address(this), address(asset), product, false);
        Position memory position = IGmxVault(gmxVault).positions(key);

        address[] memory path = new address[](1);
        path[0] = address(asset);

        uint256 acceptablePrice = IGmxVaultPriceFeed(gmxVaultPriceFeed).getPrice(product, false, false, false).mulDivDown(10 ** DECIMALS + slippageTollerance, 10 ** DECIMALS);

        IGmxPositionRouter(gmxPositionRouter).createDecreasePosition{ value: executionFee }(
            path,
            product,
            position.collateral,
            position.size,
            false,
            address(this),
            acceptablePrice,
            0,
            executionFee,
            false,
            address(0)
        );
    }

    function getPositionLeverage() public view returns (uint256 leverage) {
        try IGmxVault(gmxVault).getPositionLeverage(
                address(this),
                address(asset),
                product,
                false
            ) returns (uint256 _leverage) {
            leverage =  _leverage;
        } catch {
            return 0;
        }
    }

    function getPositionSize() public view returns (uint256 positionSize) {
        (uint256 size, , uint256 averagePrice, , , , , uint256 lastIncreasedTime) = IGmxVault(gmxVault).getPosition(
            address(this),
            address(asset),
            product,
            false
        );
        if (size == 0) {
            return 0;
        }
        (bool hasProfit, uint256 sizeDelta) = IGmxVault(gmxVault).getDelta(product, size, averagePrice, false, lastIncreasedTime);
        positionSize = hasProfit ? size + sizeDelta : size - sizeDelta;
    }

    function getPositionHedge() public view returns (uint256 positionHedge) {
        uint256 positionSize = getPositionSize();
        if (positionSize == 0) {
            return 0;
        }
        positionHedge = IGmxVault(gmxVault).usdToTokenMax(product, positionSize);
    }


    function getPositionCollateral() public view returns (uint256 remainingCollateral) {
        bytes32 key = IGmxVault(gmxVault).getPositionKey(address(this), address(asset), product, false);
        Position memory position = IGmxVault(gmxVault).positions(key);
        if (position.collateral == 0) {
            return 0;
        }
        (bool hasProfit, uint256 delta) = IGmxVault(gmxVault).getDelta(product, position.size, position.averagePrice, false, position.lastIncreasedTime);
        remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral -= delta;
        }
        remainingCollateral = remainingCollateral.mulDivDown(10 ** ASSET_DECIMALS, 10 ** GMX_PRICE_PRECISION);
    }

    function getPositionMarginFees() public view returns (uint256 marginFees) {
        bytes32 key = IGmxVault(gmxVault).getPositionKey(address(this), address(asset), product, false);
        Position memory position = IGmxVault(gmxVault).positions(key);
        marginFees = IGmxVault(gmxVault).getFundingFee(address(asset), position.size, position.entryFundingRate);
        marginFees += IGmxVault(gmxVault).getPositionFee(position.size);
    }

    function getPositionNetBalance() public view returns (uint256 marginBalance) {
        bytes32 key = IGmxVault(gmxVault).getPositionKey(address(this), address(asset), product, false);
        Position memory position = IGmxVault(gmxVault).positions(key);
        if (position.size == 0) {
            return 0;
        }
        (bool hasProfit, uint256 delta) = IGmxVault(gmxVault).getDelta(product, position.size, position.averagePrice, false, position.lastIncreasedTime);
        marginBalance = position.collateral;
        if (hasProfit) {
            marginBalance += delta;
        } else {
            marginBalance -= delta;
        }
        uint256 positionMarginFees = getPositionMarginFees();
        marginBalance -= positionMarginFees;
        marginBalance = marginBalance.mulDivDown(10 ** ASSET_DECIMALS, 10 ** GMX_PRICE_PRECISION);
    }

    /*//////////////////////////////////////////////////////////////
                            REBALANCING LOGIC
    //////////////////////////////////////////////////////////////*/


    function getHedgeRatio() public view returns (uint256) {
        uint256 exposure = getLpExposure();
        if (exposure == 0) {
            return 0;
        }
        uint256 hedge = getPositionHedge();
        if (hedge == 0) {
            return 0;
        }
        return hedge.mulDivDown(10 ** DECIMALS, exposure);
    }

    function rebalanceRequired() public view returns (bool) {
        uint256 currentHedgeRatio = getHedgeRatio();
        uint256 _rehedegeThreshold = rehedgeThreshold;
        if (currentHedgeRatio > (10 ** DECIMALS + _rehedegeThreshold) || currentHedgeRatio < (10 ** DECIMALS - _rehedegeThreshold)) {
            return true;
        } else {
            return false;
        }
    }

    function desiredLpNetBalance(uint256 _totalAssets, uint256 _targetLeverage) public pure returns (uint256) {
        return (2 * _totalAssets).mulDivDown(_targetLeverage , 2 * _targetLeverage + 10 ** DECIMALS);
    }

    function desiredPositionSize(uint256 _totalAssets, uint256 _targetLeverage) public view returns (uint256) {
        return (_totalAssets).mulDivDown(_targetLeverage, 2 * _targetLeverage + 10 ** DECIMALS).mulDivDown(10 ** GMX_PRICE_PRECISION, 10 ** ASSET_DECIMALS);
    }

    function desiredPositionHedge(uint256 _totalAssets, uint256 _tagetLeverage) public view returns (uint256) {
        uint256 _desiredLpNetBalance = desiredLpNetBalance(_totalAssets, _tagetLeverage);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        uint256 assetReserve = uint256(address(asset) < product ? reserve0 : reserve1);
        uint256 productReserve = uint256(product < address(asset) ? reserve0 : reserve1);
        uint256 productSpotPrice = assetReserve.mulDivDown(10 ** PRODUCT_DECIMALS * 10 ** ASSET_DECIMALS, productReserve * 10 ** ASSET_DECIMALS);
        uint256 desiredLpExposure = _desiredLpNetBalance.mulDivDown(10 ** ASSET_DECIMALS * 10 ** PRODUCT_DECIMALS, 2 * productSpotPrice * 10 ** ASSET_DECIMALS);
        return desiredLpExposure;
    }

    function rebalance() public onlyKeeper {
        if (rebalanceRequired()) {
            _rebalance();
        } else {
            revert("NO_REBALANCE_REQUIRED");
        }
    }

    function _rebalance() internal {
        uint256 vaultAssetBalance = asset.balanceOf(address(this));
        uint256 _targetLeverage = targetLeverage;

        // rebalance LP position
        uint256 currentLpBalance = getLpNetBalance();
        uint256 desiredLpBalance = desiredLpNetBalance(totalAssets(), _targetLeverage);
        if(currentLpBalance < desiredLpBalance) {
            // we need to increase LP position
            uint256 lpDelta = desiredLpBalance - currentLpBalance;
            lpDelta = lpDelta < vaultAssetBalance ? lpDelta : vaultAssetBalance;
            if(lpDelta > 0) {
                _addLiquidity(lpDelta);
            }
        } else if (currentLpBalance > desiredLpBalance) {
            // we need to reduce LP position
            uint256 lpDelta = currentLpBalance - desiredLpBalance;
            _removeLiquidity(lpDelta);
        }
        vaultAssetBalance = asset.balanceOf(address(this));

        // rebalance hedge position
        uint256 currentHedge = getPositionHedge();
        uint256 desiredHedge = desiredPositionHedge(totalAssets(), _targetLeverage);

        if(currentHedge > desiredHedge) {
            // we need to reduce hedge position
            uint256 hedgeDelta = currentHedge - desiredHedge;
            uint256 sizeDelta = IGmxVault(gmxVault).tokenToUsdMin(product, hedgeDelta);
            uint256 collateralDelta = sizeDelta.mulDivDown(10**DECIMALS * 10**DECIMALS , uint256(_targetLeverage) * uint256(SIZE_DELTA_MULT));
            uint256 acceptablePrice = IGmxVaultPriceFeed(gmxVaultPriceFeed).getPrice(product, false, false, false).mulDivDown(10 ** DECIMALS + slippageTollerance, 10 ** DECIMALS);

            address[] memory path = new address[](1);
            path[0] = address(asset);   

            IGmxPositionRouter(gmxPositionRouter).createDecreasePosition{ value: executionFee }(
                path,
                product,
                collateralDelta,
                sizeDelta,
                false,
                address(this),
                acceptablePrice,
                0,
                executionFee,
                false,
                address(0)
            );
        } else if (currentHedge < desiredHedge) {
            // we need to increase hedge position
            uint256 hedgeDelta = desiredHedge - currentHedge;
            uint256 price = IGmxVault(gmxVault).getMaxPrice(product);
            uint256 sizeDelta = hedgeDelta.mulDivDown(price, 10 ** PRODUCT_DECIMALS);
            sizeDelta = sizeDelta.mulDivDown(10 ** ASSET_DECIMALS, 10 ** GMX_PRICE_PRECISION);

            sizeDelta = sizeDelta < vaultAssetBalance ? sizeDelta : vaultAssetBalance;
            if(sizeDelta > 0) {
                _increaseHedge(sizeDelta);
            }
        }
        lastRebalanceTimestamp = block.timestamp;
    }

    function getVaultState() public view returns (
        uint256 vaultTotalAssets,
        uint256 assetBalance,
        uint256 lpSharesBalance,
        uint256 assetInLp,
        uint256 productInLp,
        uint256 lpNetBalance,
        uint256 positionSize,
        uint256 positionCollateral,
        uint256 positionHedge,
        uint256 positionLeverage,
        uint256 positionMarginFees,
        uint256 positionNetBalance,
        uint256 vaultHedgeRatio,
        int256 vaultPnl,
        int256 vaultApy,
        uint256 rebalanceTimestamp
    ) {
        vaultTotalAssets = totalAssets();
        assetBalance = asset.balanceOf(address(this));
        lpSharesBalance = ERC20(pool).balanceOf(address(this));
        assetInLp = getLpAssetBalance();
        productInLp = getLpExposure();
        lpNetBalance = getLpNetBalance();
        positionSize = getPositionSize();
        positionCollateral = getPositionCollateral();
        positionHedge = getPositionHedge();
        positionLeverage = getPositionLeverage();
        positionMarginFees = getPositionMarginFees();
        positionNetBalance = getPositionNetBalance();
        vaultHedgeRatio = getHedgeRatio();
        vaultPnl = getVaultPnl();
        vaultApy = getVaultApy();
        rebalanceTimestamp = lastRebalanceTimestamp;
    }

    function exitStrategy() external onlyOwner {
        _exitPosition();
        _exitLiquidity();
    }


    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return getLpNetBalance() + getPositionNetBalance() + asset.balanceOf(address(this));
    }

    function getVaultPnl() public view returns (int256 pnl) {
        if(depositedAssets == 0) {
            return int256(0);
        }
        pnl = int256(totalAssets()) - int256(depositedAssets);
    }

    function getVaultApy() public view returns (int256 apy) {
        if(depositedAssets == 0) {
            return 0;
        }
        uint256 timePassed = block.timestamp - vaultActivationTimestamp;
        if(timePassed == 0) {
            return 0;
        }
        int256 pnl = getVaultPnl();
        if(pnl >= 0) {
            apy = int256(uint256(pnl).mulDivDown(365 days * 10**DECIMALS, depositedAssets * timePassed));
        } else {
            apy = -int256(uint256(-pnl).mulDivDown(365 days * 10**DECIMALS, depositedAssets * timePassed));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function afterDeposit(uint256 assets, uint256) internal override {
        if(rebalanceRequired()) {
            _rebalance();
        }
        depositedAssets += assets;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function extCall(address target, bytes calldata data, uint256 msgvalue) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call{ value: msgvalue }(data);
        require(success, string(returnData));
        return returnData;
    }

    function sweepErc(address token) external onlyOwner {
        uint256 balance = ERC20(token).balanceOf(address(this));
        ERC20(token).transfer(msg.sender, balance);
    }

    function sweepEth() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }
 
    receive() external payable {}
}
