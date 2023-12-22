// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";


interface IUniswapV2Factory {

    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}


contract TradingHelper is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    IUniswapV2Router public uniswapV2Router;
    address public uniswapV2Pair;
    bool public pairInverse;
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // Mainnet
    
    uint256 public profitTax = 500; // users should pay 5% of trading profit
    uint256 public fundsBackTax = 15; // users should pay 0.15% of borrow amount per day
    uint256 constant feeDenominator = 10000;

    mapping(address => bool) public autoEnders;
    mapping(uint256 => uint256) public maxBorrowAmount;
    mapping(uint256 => uint256) public maxMultiplier;
    mapping(address => bool) public botBlackList;
    
    constructor(
        address _router // sushiswap: 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
    ) {
        uniswapV2Router = IUniswapV2Router(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(USDC, uniswapV2Router.WETH());
        autoEnders[msg.sender] = true;
        maxBorrowAmount[0] = 50 ether; // 50 WETH FOR WETH POOL
        maxBorrowAmount[1] = 100000 * 10 ** 6; // 10,000 USDC FOR USDC POOL
        maxMultiplier[0] = 5; // 5 FOR START
        maxMultiplier[1] = 5; // 5 FOR START
    }

    function addAutoEnder(address _account) public onlyOwner {
        autoEnders[_account] = true;
    }
    
    function removeAutoEnder(address _account) public onlyOwner {
        autoEnders[_account] = false;
    }

    function addBlackList(address _cAddress) public onlyOwner {
        require(_cAddress.isContract(), "not contract");
        botBlackList[_cAddress] = true;
    }
    
    function removeBlackList(address _cAddress) public onlyOwner {
        require(_cAddress.isContract(), "not contract");
        botBlackList[_cAddress] = false;
    }

    function setProfitTax(uint256 _tax) external onlyOwner {
        require(_tax <= 1000, "impossible to exceed 10%");
        profitTax = _tax;
    }

    function setFundsBackTax(uint256 _tax) external onlyOwner {
        require(_tax <= 100, "impossible to exceed 1%");
        fundsBackTax = _tax;
    }

    function setMaxBorrowAmount(uint256 _pid, uint256 _amount) external onlyOwner {       
        maxBorrowAmount[_pid] = _amount;
    }

    function setMaxMultiplier(uint256 _pid, uint256 _multiplier) external onlyOwner {       
        require(_multiplier >= 5, 'too low');
        maxMultiplier[_pid] = _multiplier;
    }

    function getMaxBorrowAmount(uint256 _pid) public view returns (uint256) {
        return maxBorrowAmount[_pid];
    }

    function getMaxMultiplier(uint256 _pid) public view returns (uint256) {
        return maxMultiplier[_pid];
    }

    function setRouter(address _router) external onlyOwner{
        require(address(uniswapV2Router) != _router, "already set same address");
        uniswapV2Router = IUniswapV2Router(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(USDC, uniswapV2Router.WETH());
    }

    function isAutoEnder(address _account) public view returns (bool) {
        return autoEnders[_account];
    }

    function getETHprice() public view returns (uint256) {
        (uint Res0, uint Res1, ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        if(pairInverse) {
            return Res0.mul(1e14).div(Res1);
        } else {
            return Res1.mul(1e14).div(Res0);
        }
    }

    // Swap USDC to WETH
    function SwapToWETH(uint256 _inAmount) external returns (uint _outAmount){
        require(!botBlackList[tx.origin], "bot not allowed");
        if(_inAmount == 0) {
            _outAmount = 0;
        }
        else {
            IERC20(USDC).safeTransferFrom(msg.sender, address(this), _inAmount);

            if (IERC20(USDC).allowance(msg.sender, address(uniswapV2Router)) < _inAmount) {
                IERC20(USDC).safeApprove(address(uniswapV2Router), _inAmount);
            }
            address[] memory path;
            path = new address[](2);
            path[0] = USDC;
            path[1] = uniswapV2Router.WETH();

            uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
                _inAmount,
                0,
                path,
                msg.sender,
                block.timestamp
            );
            _outAmount = amounts[amounts.length - 1];
        }
    }

    // Swap WETH to USDC
    function SwapWETH(uint256 _inAmount) external returns (uint _outAmount){
        require(!botBlackList[tx.origin], "bot not allowed");
        if(_inAmount == 0) {
            _outAmount = 0;
        }
        else {
            address WETH = uniswapV2Router.WETH();
            IERC20(WETH).safeTransferFrom(msg.sender, address(this), _inAmount);

            if (IERC20(WETH).allowance(msg.sender, address(uniswapV2Router)) < _inAmount) {
                IERC20(WETH).safeApprove(address(uniswapV2Router), _inAmount);
            }

            address[] memory path;
            path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;

            uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
                _inAmount,
                0,
                path,
                msg.sender,
                block.timestamp
            );
            _outAmount = amounts[amounts.length - 1];
        }
    }

    function getEstimateWETH(uint256 inAmount) external view returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = USDC;
        path[1] = uniswapV2Router.WETH();

        uint256[] memory amounts = uniswapV2Router.getAmountsOut(inAmount, path);
        return amounts[amounts.length -1];

    }

    function getEstimateUSDC(uint256 inAmount) external view returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = USDC;

        uint256[] memory amounts = uniswapV2Router.getAmountsOut(inAmount, path);
        return amounts[amounts.length -1];
    }

}
