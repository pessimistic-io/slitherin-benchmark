// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";
import "./ETHUnwrapper.sol";

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) 
        external 
        returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

}
interface IOracle {
    function getLastPrice(address token) external view returns (uint256 lastPrice);
}
interface IPool {
    function withdrawFee(address _token, address _recipient) external;
    function isAsset(address _token) external view returns (bool);
}

interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
}

contract FeeVault is OwnableUpgradeable{

    using SafeERC20 for IERC20;

    address public  router;
    address public  veToken;
    address public weth;
    address public oracle;
    uint256 public generationRateETH;
    uint256 public accruedWeth;
    uint256 public accruedFees;
    uint256 public lastTimestamp;
    ETHUnwrapper public ethUnwrapper;
    mapping(address => uint256) public accruedFeesPool;

    receive() external payable {   
    }

    modifier onlyVeToken() {
        require(veToken == msg.sender, "onlyVeToken: caller is not the veToken");
        _;
    }

    function initialize(
        address _router,
        address _veToken,
        address _oracle,
        ETHUnwrapper _ethUnwrapper,
        uint256 _generationRateETH
    ) public initializer {
        __Ownable_init_unchained();
        router = _router;
        veToken = _veToken;
        oracle = _oracle;
        weth = IUniswapV2Router01(_router).WETH();
        generationRateETH = _generationRateETH;
        ethUnwrapper = _ethUnwrapper;
        lastTimestamp = block.timestamp;
    }

    function setVeToken(address _veToken) external onlyOwner{
        require(_veToken != address(0), "new veToken is the zero address");
        veToken = _veToken;
    }

    function setOracle(address _oracle) external onlyOwner{
        require(_oracle != address(0), "new oracle is the zero address");
        oracle = _oracle;
    }

    function setGenerationRateETH(uint256 _generationRateETH) external onlyOwner {
        //require(_generationRateETH != 0, "generation rate cannot be zero");
        generationRateETH = _generationRateETH;
    }
    

    function distribute(address _user,uint256 _amount) external onlyVeToken{
        IWETH(weth).deposit{value: address(this).balance}();
        uint256 balance = IERC20(weth).balanceOf(address(this));
        if(balance > _amount){
            _safeUnwrapETH(_amount, _user);
        }else{
            _safeUnwrapETH(balance, _user);
        }
    }

    function _withdrawFee(IPool _pool, address _token) internal returns (uint256) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        _pool.withdrawFee(_token, address(this));
        return IERC20(_token).balanceOf(address(this)) - balance;
    }

    function withdrawFee(IPool[] memory pools, address _token, address[] memory _path) external onlyOwner{
        uint256 decimals = IERC20Metadata(weth).decimals();
        for (uint i = 0; i < pools.length; i++) {
            IPool pool = pools[i];
            if(IPool(pool).isAsset(_token) == true){
                uint256 price = IOracle(oracle).getLastPrice(weth);
                uint256 bal = 0;

                if (_path.length == 0 && _token == weth) {
                    bal = _withdrawFee(pool, _token);
                } else {
                    require(_path[0] == _token && _path[_path.length - 1] == weth, "to token must be weth");
                    _withdrawFee(pool, _token);
                    bal = _swapSingle(_path);
                }

                uint256 value = bal * price / 10 ** (30 - decimals);
                accruedWeth += bal;
                accruedFees += value;
                lastTimestamp = block.timestamp;
                accruedFeesPool[address(pool)] += value;
            }
        }
    }

    function _swapSingle(address[] memory _path) internal returns (uint256 out) {
        uint256 balance = IERC20(_path[0]).balanceOf(address(this));
        uint256 amountOut  = IUniswapV2Router01(router).getAmountsOut(balance, _path)[_path.length - 1];
        if(amountOut > 0){
            IERC20(_path[0]).safeApprove(router, balance);
            out = IERC20(_path[_path.length - 1]).balanceOf(address(this));
            IUniswapV2Router01(router).swapExactTokensForTokens(balance, amountOut * 95 / 100, _path, address(this), block.timestamp + 1000);
            out = IERC20(_path[_path.length - 1]).balanceOf(address(this)) - out;
        }
    }

    function swapSingle(address _pool, address[] memory _path) public onlyOwner{
        uint256 price = IOracle(oracle).getLastPrice(weth);
        uint256 decimals = IERC20Metadata(weth).decimals();
        uint256 balance = IERC20(_path[0]).balanceOf(address(this));
        uint256 amountOut  = IUniswapV2Router01(router).getAmountsOut(balance, _path)[_path.length - 1];
        require(IPool(_pool).isAsset(_path[0]) == true,"token is not this pool");
        if(amountOut > 0){
            IERC20(_path[0]).safeApprove(router, balance);
            IUniswapV2Router01(router).swapExactTokensForTokens(balance, amountOut * 95 / 100, _path, address(this), block.timestamp + 1000);
            accruedWeth += amountOut;
            uint256 value = amountOut * price / 10 ** (30 - decimals);
            accruedFees += value;
            lastTimestamp = block.timestamp;
            accruedFeesPool[_pool] += value;
        }
    }
    
    function _safeUnwrapETH(uint256 _amount, address _to) internal {
        IERC20(weth).safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }
}

