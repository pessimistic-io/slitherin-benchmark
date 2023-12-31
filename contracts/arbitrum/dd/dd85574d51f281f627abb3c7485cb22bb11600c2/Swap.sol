// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import { SwapLib } from "./SwapLib.sol";
import { SafeMath } from "./math_SafeMath.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { IERC20 } from "./ERC20_IERC20.sol";
import { SafeERC20 } from "./ERC20_SafeERC20.sol";
import { IController } from "./interfaces_IController.sol";
import { IZeroModule } from "./IZeroModule.sol";

contract Swap is IZeroModule {
  using SafeERC20 for *;
  using SafeMath for *;
  mapping(uint256 => SwapLib.SwapRecord) public outstanding;
  address public immutable controller;
  address public immutable governance;
  uint256 public blockTimeout;
  address public immutable fiat; //USDC
  address public immutable wNative; //wETH
  address public immutable override want; //wBTC
  address public immutable router; //Sushi V2
  address public immutable controllerWant; // Controller want (renBTC)

  modifier onlyController() {
    require(msg.sender == controller, "!controller");
    _;
  }

  constructor(
    address _controller,
    address _wNative,
    address _want,
    address _router,
    address _fiat,
    address _controllerWant
  ) {
    controller = _controller;
    wNative = _wNative;
    want = _want;
    router = _router;
    fiat = _fiat;
    controllerWant = _controllerWant;
    governance = IController(_controller).governance();
    IERC20(_want).safeApprove(_router, ~uint256(0));
    IERC20(_fiat).safeApprove(_router, ~uint256(0));
  }

  function setBlockTimeout(uint256 _ct) public {
    require(msg.sender == governance, "!governance");
    blockTimeout = _ct;
  }

  function defaultLoan(uint256 _nonce) public {
    require(block.number >= outstanding[_nonce].when + blockTimeout);
    require(outstanding[_nonce].qty != 0, "!outstanding");
    uint256 _amountSwapped = swapTokens(fiat, controllerWant, outstanding[_nonce].qty);
    IERC20(controllerWant).safeTransfer(controller, _amountSwapped);
    delete outstanding[_nonce];
  }

  function receiveLoan(
    address _to,
    address _asset,
    uint256 _actual,
    uint256 _nonce,
    bytes memory _data
  ) public override onlyController {
    uint256 amountSwapped = swapTokens(want, fiat, _actual);
    outstanding[_nonce] = SwapLib.SwapRecord({ qty: amountSwapped, when: uint64(block.timestamp), token: _asset });
  }

  function swapTokens(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn
  ) internal returns (uint256) {
    address[] memory _path = new address[](3);
    _path[0] = _tokenIn;
    _path[1] = wNative;
    _path[2] = _tokenOut;
    IERC20(_tokenIn).approve(router, _amountIn);
    uint256 _amountOut = IUniswapV2Router02(router).swapExactTokensForTokens(
      _amountIn,
      1,
      _path,
      address(this),
      block.timestamp
    )[_path.length - 1];
    return _amountOut;
  }

  function repayLoan(
    address _to,
    address _asset,
    uint256 _actualAmount,
    uint256 _nonce,
    bytes memory _data
  ) public override onlyController {
    require(outstanding[_nonce].qty != 0, "!outstanding");
    IERC20(fiat).safeTransfer(_to, outstanding[_nonce].qty);
    delete outstanding[_nonce];
  }

  function computeReserveRequirement(uint256 _in) external view override returns (uint256) {
    return _in.mul(uint256(1e17)).div(uint256(1 ether));
  }
}

