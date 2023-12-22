// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IPool} from "./IPool.sol";
import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";

abstract contract StakingReserve is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IERC20 public LLP;
    IWETH public WETH;

    IPool public pool;
    IETHUnwrapper public ethUnwrapper;
    address public distributor;

    /// @notice the protocol generate fee in the form of these tokens
    mapping(address => bool) public feeTokens;
    /// @notice list of tokens allowed to convert to LLP. Other fee tokens MUST be manual swapped to these tokens before converting
    address[] public convertLLPTokens;
    /// @notice tokens allowed to convert to LLP, in form of map for fast checking
    mapping(address => bool) public isConvertLLPTokens;

    modifier onlyDistributorOrOwner() {
        _checkDistributorOrOwner();
        _;
    }

    function __StakingReserve_init(address _pool, address _llp, address _weth, address _ethUnwrapper)
        internal
        onlyInitializing
    {
        require(_pool != address(0), "Invalid address");
        require(_llp != address(0), "Invalid address");
        require(_weth != address(0), "Invalid address");
        require(_ethUnwrapper != address(0), "Invalid address");
        __Ownable_init();
        pool = IPool(_pool);
        LLP = IERC20(_llp);
        WETH = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
    }

    // =============== RESTRICTED ===============
    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyDistributorOrOwner
    {
        require(_toToken != _fromToken, "Invalid path");
        require(feeTokens[_fromToken] && feeTokens[_toToken], "Only feeTokens");
        uint256 _balanceBefore = IERC20(_toToken).balanceOf(address(this));
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        // self check slippage, so we send minAmountOut as 0
        pool.swap(_fromToken, _toToken, 0, address(this), abi.encode(msg.sender));
        uint256 _actualAmountOut = IERC20(_toToken).balanceOf(address(this)) - _balanceBefore;
        require(_actualAmountOut >= _minAmountOut, "!slippage");
        emit Swap(_fromToken, _toToken, _amountIn, _actualAmountOut);
    }

    /**
     * @notice operator can withdraw some tokens to manual swap or bridge to other chain's staking contract
     */
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyDistributorOrOwner {
        require(feeTokens[_token], "Only feeTokens");
        require(_to != address(0), "Invalid address");
        _safeTransferToken(_token, _to, _amount);
        emit TokenWithdrawn(_to, _amount);
    }

    function setDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "Invalid address");
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    function setConvertLLPTokens(address[] memory _tokens) external onlyOwner {
        for (uint8 i = 0; i < convertLLPTokens.length;) {
            isConvertLLPTokens[convertLLPTokens[i]] = false;
            unchecked {
                ++i;
            }
        }
        for (uint8 i = 0; i < _tokens.length;) {
            require(_tokens[i] != address(0), "Invalid address");
            isConvertLLPTokens[_tokens[i]] = true;
            unchecked {
                ++i;
            }
        }
        convertLLPTokens = _tokens;
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _checkDistributorOrOwner() internal view virtual {
        require(msg.sender == distributor || msg.sender == owner(), "Caller is not the distributor or owner");
    }

    function _setFeeToken(address _token, bool _allowed) internal {
        if (feeTokens[_token] != _allowed) {
            feeTokens[_token] = _allowed;
            emit FeeTokenSet(_token, _allowed);
        }
    }

    function _convertTokenToLLP(address _token, uint256 _amount) internal {
        require(isConvertLLPTokens[_token], "Invalid token");
        if (_amount != 0) {
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(address(LLP), _token, _amount, 0, address(this));
        }
    }

    function _convertLLPToToken(address _to, uint256 _amount, address _tokenOut, uint256 _minAmountOut)
        internal
        returns (uint256)
    {
        LLP.safeIncreaseAllowance(address(pool), _amount);
        uint256 _balanceBefore = IERC20(_tokenOut).balanceOf(address(this));
        pool.removeLiquidity(address(LLP), _tokenOut, _amount, _minAmountOut, address(this));
        uint256 _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;
        require(_amountOut >= _minAmountOut, "!slippage");
        _safeTransferToken(_tokenOut, _to, _amountOut);
        return _amountOut;
    }

    function _safeTransferToken(address _token, address _to, uint256 _amount) internal {
        if (_amount > 0) {
            if (_token == address(WETH)) {
                _safeUnwrapETH(_to, _amount);
            } else {
                IERC20(_token).safeTransfer(_to, _amount);
            }
        }
    }

    function _safeUnwrapETH(address _to, uint256 _amount) internal {
        WETH.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    // =============== EVENTS ===============
    event DistributorSet(address indexed _distributor);
    event FeeTokenSet(address indexed _token, bool _allowed);
    event Swap(address indexed _tokenIn, address indexed _tokenOut, uint256 _amountIn, uint256 _amountOut);
    event TokenWithdrawn(address indexed _to, uint256 _amount);
}

