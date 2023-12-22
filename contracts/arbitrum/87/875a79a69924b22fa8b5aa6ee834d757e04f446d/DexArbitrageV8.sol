// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IDBXRouter.sol";
import "./IWETH.sol";
import "./IAnalizeModule.sol";


contract DexArbitrageV8 is Ownable {
  using SafeERC20 for IERC20;

  uint256 public constant DIVIDER = 10000;
  uint256 public constant PRECISION = 10 ** 18;


    address public wethAddress;
    address public wbtcAddress;
    address public uniswapRouterAddress;
    address public dbxRouterAddress;

    address public module;

    address public keeper;

    uint256 public minProfit;

    uint256 public uniswapFee;

    uint256 public minBalanceKeeper;
    uint256 public increaseBalanceKeeperAmount;

    uint256 public minBalanceWeth;
    uint256 public minBalanceWbtc;
    uint256 public minProfitToWithdrawWeth;
    uint256 public minProfitToWithdrawWbtc;

    address public profitReceiver0;
    address public profitReceiver1;
    uint256 public profitDistribution;

    uint256 public wethAmountForArbitrage;
    uint256 public wbtcAmountForArbitrage;


    constructor(
        address _uniswapRouterAddress,
        address _dbxRouterAddress,
        address _weth,
        address _wbtc
    ) {
        uniswapRouterAddress = _uniswapRouterAddress;
        dbxRouterAddress = _dbxRouterAddress;
        wethAddress = _weth;
        wbtcAddress = _wbtc;
    }

    function setMinProfit(uint256 _minProfit) external onlyOwner returns (bool) {
        require(_minProfit < DIVIDER, "DexArbitrage: MinProfit gt DIVIDER");
        minProfit = _minProfit;
        return true;
    }

    function setUniswapFee(uint256 _uniswapFee) external onlyOwner returns (bool) {
        require(_uniswapFee < DIVIDER, "DexArbitrage: RatioDelta gt DIVIDER");
        uniswapFee = _uniswapFee;
        return true;
    }

    function setModule(address _module) external onlyOwner returns (bool) {
        require(_module != address(0), "DexArbitrage: Module's address is zero");
        module = _module;
        return true;
    }

    function setKeeper(address _keeper) external onlyOwner returns (bool) {
        require(_keeper != address(0), "DexArbitrage: Keeper's address is zero");
        keeper = _keeper;
        return true;
    }

    function setProfitInfo(address _receiver0, address _receiver1, uint256 _distribution) external onlyOwner returns (bool) {
        require(_receiver0 != address(0), "DexArbitrage: ProfitReceiver's address is zero");
        require(_receiver1 != address(0), "DexArbitrage: ProfitReceiver's address is zero");
        require(_distribution < DIVIDER, "DexArbitrage: ProfitDistribution gt DIVIDER");
        profitReceiver0 = _receiver0;
        profitReceiver1 = _receiver1;
        profitDistribution = _distribution;
        return true;
    }

    function setMinBalanceKeeper(uint256 _minBalance) external onlyOwner returns (bool) {
        minBalanceKeeper = _minBalance;
        return true;
    }

    function setIncreaseBalanceKeeperAmount(uint256 _amount) external onlyOwner returns (bool) {
        increaseBalanceKeeperAmount = _amount;
        return true;
    }

    function setMinBalanceWeth(uint256 _minBalance) external onlyOwner returns (bool) {
        minBalanceWeth = _minBalance;
        return true;
    }

    function setminBalanceWbtc(uint256 _minBalance) external onlyOwner returns (bool) {
        minBalanceWbtc = _minBalance;
        return true;
    }

    function setMinProfitToWithdrawWeth(uint256 _minProfit) external onlyOwner returns (bool) {
        minProfitToWithdrawWeth = _minProfit;
        return true;
    }

    function setMinProfitToWithdrawWbtc(uint256 _minProfit) external onlyOwner returns (bool) {
        minProfitToWithdrawWbtc = _minProfit;
        return true;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "DexArbitrage: Identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DexArbitrage: Zero address");
    }

    function estimation() public view returns (address tokenIn, uint256 amountIn) {
        (tokenIn, amountIn) = IAnalizeModule(module).moduleEstimation(uniswapRouterAddress, dbxRouterAddress, wethAddress, wbtcAddress); 
    }


    function arbitrageExecute() public returns (address token, uint256 profit) {

        (address tokenIn, uint256 amountIn) = estimation();
        require(amountIn > 0, "DexArbitrage: Amount is zero");

        if (tokenIn == wbtcAddress) {
            if (amountIn > wbtcAmountForArbitrage) amountIn = wbtcAmountForArbitrage;
            uint256 balanceBefore = IERC20(wbtcAddress).balanceOf(address(this));

            uint256 amountIntermediate = _swap(amountIn, dbxRouterAddress, wbtcAddress, wethAddress);
            _swap(amountIntermediate, uniswapRouterAddress, wethAddress, wbtcAddress);

            uint256 balanceAfter = IERC20(wbtcAddress).balanceOf(address(this));

            if (balanceAfter > balanceBefore) {
                profit = balanceAfter - balanceBefore;
            } else {
                profit = 0;
            }
            require(profit * DIVIDER / amountIn > minProfit, "DexArbitrage: Profit lt min");

            wbtcAmountForArbitrage = balanceAfter;

            token = tokenIn;

        } else {
            if (amountIn > wethAmountForArbitrage) amountIn = wethAmountForArbitrage;
            uint256 balanceBefore = IERC20(wethAddress).balanceOf(address(this));

            uint256 amountIntermediate = _swap(amountIn, dbxRouterAddress, wethAddress, wbtcAddress);
            _swap(amountIntermediate, uniswapRouterAddress, wbtcAddress, wethAddress);

            uint256 balanceAfter = IERC20(wethAddress).balanceOf(address(this));

            if (balanceAfter > balanceBefore) {
                profit = balanceAfter - balanceBefore;
            } else {
                profit = 0;
            }
            require(profit * DIVIDER / amountIn > minProfit, "DexArbitrage: Profit lt min");

            wethAmountForArbitrage = balanceAfter;

            token = tokenIn;

            claimProfit();

            addKeeperFund();

        }
    }


    function calculateRatios() public view returns (uint256 ratioUniswap, uint256 ratioDbx, bool needForArbitrage, uint256 nTarget, uint256 nReal) {
        (ratioUniswap, ratioDbx, needForArbitrage, nTarget, nReal) = IAnalizeModule(module).moduleCalculateRatios(uniswapRouterAddress, dbxRouterAddress, wethAddress, wbtcAddress, uniswapFee);
    }


    function _getPriceUniswap(address routerAddress, address tokenIn, address tokenOut, uint256 amount) internal view returns (uint256) {
        address[] memory pairs = new address[](2);
        pairs[0] = tokenIn;
        pairs[1] = tokenOut;
        uint256 receiveAmount = IUniswapV2Router02(routerAddress).getAmountsOut(amount, pairs)[1];
        return receiveAmount;
    }

    function _getPriceDbx(address routerAddress, address tokenIn, address tokenOut, uint256 amount) internal view returns (uint256) {
        address[] memory pairs = new address[](2);
        pairs[0] = tokenIn;
        pairs[1] = tokenOut;
        uint256 receiveAmount = IDegenBrainsRouter02(routerAddress).getAmountsOut(amount, pairs)[1];
        return receiveAmount;
    }

    function _swap(uint256 amountIn, address routerAddress, address tokenIn, address tokenOut) internal returns (uint256) {
        IERC20(tokenIn).approve(routerAddress, amountIn);

        if (routerAddress == uniswapRouterAddress) {
            uint256 amountOutMin = _getPriceUniswap(routerAddress, tokenIn, tokenOut, (amountIn * 90) / 100);

            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            IERC20(tokenIn).approve(routerAddress, amountIn);
            uint256 amountOut = IUniswapV2Router02(routerAddress).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp)[1];
            return amountOut;

        } else if (routerAddress == dbxRouterAddress) {
            uint256 amountOutMin = _getPriceDbx(routerAddress, tokenIn, tokenOut, (amountIn * 90) / 100);

            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            IERC20(tokenIn).approve(routerAddress, amountIn);
            uint256 amountOut = IDegenBrainsRouter02(routerAddress).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp)[1];
            return amountOut;

        } else {
            return 0;
        }
    }


    function claimProfit() private {
        uint256 amountWethToClaim = wethAmountForArbitrage < minBalanceWeth 
            ? 0 
            : (wethAmountForArbitrage - minBalanceWeth >= minProfitToWithdrawWeth) 
            ? wethAmountForArbitrage - minBalanceWeth 
            : 0;

        uint256 amountWbtcToClaim = wbtcAmountForArbitrage < minBalanceWbtc 
            ? 0 
            : (wbtcAmountForArbitrage - minBalanceWbtc >= minProfitToWithdrawWbtc) 
            ? wbtcAmountForArbitrage - minBalanceWbtc 
            : 0;

        if (amountWethToClaim > 0) {
            uint256 wethToReceiver0 = amountWethToClaim * profitDistribution / DIVIDER;
            uint256 wethToReceiver1 = amountWethToClaim - wethToReceiver0;
            IERC20(wethAddress).safeTransfer(profitReceiver0, wethToReceiver0);
            IERC20(wethAddress).safeTransfer(profitReceiver1, wethToReceiver1);
        }
        
        if (amountWbtcToClaim > 0) {
            uint256 wbtcToReceiver0 = amountWbtcToClaim * profitDistribution / DIVIDER;
            uint256 wbtcToReceiver1 = amountWbtcToClaim - wbtcToReceiver0;
            IERC20(wbtcAddress).safeTransfer(profitReceiver0, wbtcToReceiver0);
            IERC20(wbtcAddress).safeTransfer(profitReceiver1, wbtcToReceiver1);
        }

        wethAmountForArbitrage -= amountWethToClaim;
        wbtcAmountForArbitrage -= amountWbtcToClaim;
    }


    function checkKeeperBalance() public view returns (uint256) {
        return keeper.balance;
    }

    function addKeeperFund() private {
        uint256 keeperBalance = checkKeeperBalance();
        if (keeper != address(0) && keeperBalance < minBalanceKeeper) {
            IWETH(wethAddress).withdraw(increaseBalanceKeeperAmount);
            wethAmountForArbitrage -= increaseBalanceKeeperAmount;
            payable(keeper).transfer(increaseBalanceKeeperAmount);
        }  
    }


    function deposit(address token, uint256 amount) public onlyOwner returns (bool) {
        require(amount > 0, "Deposit amount must be greater than 0");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (token == wbtcAddress) wbtcAmountForArbitrage += amount;
        if (token == wethAddress) wethAmountForArbitrage += amount;
        return true;
    }

    function withdraw(address token, uint256 amount, address to) public onlyOwner returns (bool) {
        require(amount <= IERC20(token).balanceOf(address(this)), "Not enough fund for withdraw");
        IERC20(token).safeTransfer(to, amount);
        if (token == wbtcAddress) wbtcAmountForArbitrage -= amount;
        if (token == wethAddress) wethAmountForArbitrage -= amount;
        return true;
    }


    function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOwner returns (bool) {
        _token.safeTransfer(_to, _amount);
        return true;
    }

    receive() external payable {}
}

