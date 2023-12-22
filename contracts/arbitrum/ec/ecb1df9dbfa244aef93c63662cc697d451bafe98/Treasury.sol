// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {IPool} from "./IPool.sol";
import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";

contract Treasury is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IWETH public constant weth = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IETHUnwrapper public constant ethUnwrapper = IETHUnwrapper(0x38EE8A935d1aCB254DC1ae3cb3E3d2De41Fe3e7B);

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    uint256 public constant RATIO_PRECISION = 100;
    uint8 public constant VERSION = 2;

    IPool public constant pool = IPool(0x32B7bF19cb8b95C27E644183837813d4b595dcc6);
    address public constant LLP = 0x5573405636F4b895E511C9C54aAfbefa0E7Ee458;

    address public lgoRedemptionPool;

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function convertToLLP(address _token, uint256 _amount, uint256 _minAmountOut)
        external
        nonReentrant
        onlyRole(CONTROLLER_ROLE)
    {
        uint256 amountOut = _addLiquidity(_token, _amount, LLP, _minAmountOut, address(this));
        emit LLPConverted(_token, LLP, _amount, amountOut);
    }

    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        require(_toToken != _fromToken, "invalidPath");
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        uint256 balanceBefore = IERC20(_toToken).balanceOf(address(this));
        pool.swap(_fromToken, _toToken, _minAmountOut, address(this), abi.encode(msg.sender));
        uint256 actualAmountOut = IERC20(_toToken).balanceOf(address(this)) - balanceBefore;
        require(actualAmountOut >= _minAmountOut, ">slippage");
        emit Swap(_fromToken, _toToken, _amountIn, actualAmountOut);
    }

    function distribute(address _token, address _receiver, uint256 _amount) external {
        require(msg.sender == lgoRedemptionPool, "Treasury::only LGO redemption pool");
        require(_token != address(0), "Treasury::invalid token address");
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit TokenDistributed(lgoRedemptionPool, _token, _receiver, _amount);
    }

    /* ========== RESTRICTED ========== */

    function recoverFund(address _token, address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), "Treasury::recoverFund: invalid address");
        require(_token != address(0), "Treasury::recoverFund: invalid address");
        IERC20(_token).safeTransfer(_to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    function setLgoRedemptionPool(address _lgoRedemptionPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lgoRedemptionPool != address(0), "Treasury::invalid address");
        lgoRedemptionPool = _lgoRedemptionPool;
        emit LgoRedemptionPoolSet(_lgoRedemptionPool);
    }
    /* ========== INTERNAL FUNCTION ========== */

    function _addLiquidity(address _token, uint256 _amount, address _llp, uint256 _minAmountOut, address _to)
        internal
        returns (uint256 actualLPAmountOut)
    {
        uint256 lpBalanceBefore = IERC20(_llp).balanceOf(_to);
        IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
        pool.addLiquidity(_llp, _token, _amount, _minAmountOut, _to);
        actualLPAmountOut = IERC20(_llp).balanceOf(_to) - lpBalanceBefore;
    }

    function _safeUnwrapETH(uint256 _amount, address _to) internal {
        weth.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    /* ========== EVENTS ========== */
    event LLPConverted(address indexed token, address indexed llp, uint256 amount, uint256 lpAmountOut);
    event TokenDistributed(address indexed spender, address token, address receiver, uint256 amount);
    event LLPTokenSet(address indexed token);
    event LgoRedemptionPoolSet(address indexed token);
    event WithdrawableTokenAdded(address indexed token);
    event WithdrawableTokenRemoved(address indexed token);
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
}

