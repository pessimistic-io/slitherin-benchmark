// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IDexSwapRouter.sol";
import "./IDirectUSDEXMinter.sol";
import "./IWETH.sol";
import "./IStabilizeModule.sol";


contract DexStabilizerV2 is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant DIVIDER = 10000;
    uint256 public constant PRECISION = 10 ** 18;

    address public usdexAddress;
    address public usdcAddress;
    address public wethAddress;

    uint8 public usdcDecimals;
    uint8 public usdexDecimals;

    address public dexSwapRouterAddress;
    IDirectUSDEXMinter public usdexMinter;

    address public module;

    address public admin;
    address public keeper;

    uint256 public minBalanceKeeper;
    uint256 public increaseUSDCBalanceKeeperAmount;

    uint256 public minProfit;


    constructor(
        address _dexSwapRouterAddress,
        address _usdex,
        address _usdc,
        address _weth,
        address _usdexMinter,
        address _admin
    ) {
        dexSwapRouterAddress = _dexSwapRouterAddress;
        usdexAddress = _usdex;
        usdcAddress = _usdc;
        wethAddress = _weth;
        usdcDecimals = IERC20Metadata(usdcAddress).decimals();
        usdexDecimals = IERC20Metadata(usdexAddress).decimals();
        usdexMinter = IDirectUSDEXMinter(_usdexMinter);
        admin = _admin;
    }

    function setAdmin(address _newAdmin) external returns (bool) {
        require(msg.sender == owner() || msg.sender == admin, "DexStabilizer: Caller is not the owner or admin");
        require(admin != address(0), "DexStabilizer: Admin's address is zero");
        admin = _newAdmin;
        return true;
    }

    function setModule(address _module) external onlyAdmin returns (bool) {
        require(_module != address(0), "DexStabilizer: Module's address is zero");
        module = _module;
        return true;
    }

    function setMinProfit(uint256 _minProfit) external onlyAdmin returns (bool) {
        minProfit = _minProfit;
        return true;
    }

    function setKeeper(address _keeper) external onlyAdmin returns (bool) {
        require(_keeper != address(0), "DexStabilizer: Keeper's address is zero");
        keeper = _keeper;
        return true;
    }

    function setMinBalanceKeeper(uint256 _minBalance) external onlyAdmin returns (bool) {
        minBalanceKeeper = _minBalance;
        return true;
    }

    function setIncreaseUSDCBalanceKeeperAmount(uint256 _amount) external onlyAdmin returns (bool) {
        increaseUSDCBalanceKeeperAmount = _amount;
        return true;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "DexStabilizer: Identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DexStabilizer: Zero address");
    }


    function estimation() public view returns (address tokenIn, uint256 amountIn, uint256 profit, uint256 ratio) {
        (tokenIn, amountIn, profit, ratio) = IStabilizeModule(module).moduleEstimation(dexSwapRouterAddress, usdexAddress, usdcAddress, usdexDecimals, usdcDecimals); 
    }

    function arbitrageExecute() public returns (bool) {
        (address tokenIn, uint256 amountIn, uint256 profit,) = estimation();
        require(amountIn > 0, "DexStabilizer: Amount is zero");
        require(profit > 0, "DexStabilizer: Profit is zero");

        uint256 usdcAmountForArbitrage = IERC20(usdcAddress).balanceOf(address(this));
        uint256 usdexAmountForArbitrage = IERC20(usdexAddress).balanceOf(address(this));

        if (tokenIn == usdcAddress) {
            if (amountIn > usdcAmountForArbitrage) amountIn = usdcAmountForArbitrage;
            _swap(amountIn, usdcAddress, usdexAddress);
            require(profit * PRECISION / (10 ** usdcDecimals) > minProfit, "DexStabilizer: Profit lt min");
        } else {
            if (amountIn > usdexAmountForArbitrage) {
                uint256 amountUsdexToBuy = (amountIn - usdexAmountForArbitrage) * 105 / 100;
                uint256 amountUsdcToSell = amountUsdexToBuy * (10 ** usdcDecimals) / (10 ** usdexDecimals);
                IERC20(usdcAddress).approve(address(usdexMinter), amountUsdcToSell);
                usdexMinter.mint(amountUsdcToSell);
            }
            _swap(amountIn, usdexAddress, usdcAddress);
            require(profit * PRECISION / (10 ** usdexDecimals) > minProfit, "DexStabilizer: Profit lt min");
        }

        addKeeperFund();
        return true;
    }

    function _swap(uint256 amountIn, address tokenIn, address tokenOut) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IERC20(tokenIn).approve(dexSwapRouterAddress, amountIn);
        uint256 amountOut = IDexSwapRouter02(dexSwapRouterAddress).swapExactTokensForTokens(amountIn, 1, path, address(this), block.timestamp)[1];
        return amountOut;
    }

    function checkKeeperBalance() public view returns (uint256) {
        return keeper.balance;
    }

    function addKeeperFund() private {
        uint256 keeperBalance = checkKeeperBalance();
        if (keeper != address(0) && keeperBalance < minBalanceKeeper && increaseUSDCBalanceKeeperAmount < IERC20(usdcAddress).balanceOf(address(this))) {

            _swap(increaseUSDCBalanceKeeperAmount, usdcAddress, wethAddress);
            uint256 wethBalance = IERC20(wethAddress).balanceOf(address(this));

            IWETH(wethAddress).withdraw(wethBalance);
            payable(keeper).transfer(wethBalance);
        }  
    }

    function usdcBalance() external view returns (uint256) {
        return IERC20(usdcAddress).balanceOf(address(this));
    }

    function usdexBalance() external view returns (uint256) {
        return IERC20(usdexAddress).balanceOf(address(this));
    }

    function deposit(address token, uint256 amount) public onlyOwner returns (bool) {
        require(amount > 0, "DexStabilizer: Deposit amount must be greater than 0");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        return true;
    }

    function withdraw(address token, uint256 amount, address to) public onlyOwner returns (bool) {
        require(amount <= IERC20(token).balanceOf(address(this)), "DexStabilizer: Not enough fund for withdraw");
        IERC20(token).safeTransfer(to, amount);
        return true;
    }

    function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOwner returns (bool) {
        _token.safeTransfer(_to, _amount);
        return true;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "DexStabilizer: Caller is not the admin");
        _;
    }

    receive() external payable {}
}

