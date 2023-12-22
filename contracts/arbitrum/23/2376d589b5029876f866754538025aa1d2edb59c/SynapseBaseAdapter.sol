// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./ISynapse.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Adapter.sol";

contract SynapseBaseAdapter is Adapter {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant id = keccak256("SynapseBaseAdapter");
    uint256 public constant poolFeeCompliment = 9996; // In bips
    uint256 public constant bips = 1e4;
    mapping(address => bool) public isPoolToken;
    mapping(address => uint8) public tokenIndex;
    uint8 public numberOfTokens = 0;
    address public pool;

    constructor(
        string memory _name,
        address _pool,
        uint256 _swapGasEstimate
    ) public {
        pool = _pool;
        name = _name;
        _setPoolTokens();
        setSwapGasEstimate(_swapGasEstimate);
    }

    // Mapping indicator which tokens are included in the pool
    function _setPoolTokens() internal {
        // Get stables from pool
        for (uint8 i = 0; true; i++) {
            try ISynapse(pool).getToken(i) returns (IERC20 token) {
                isPoolToken[address(token)] = true;
                tokenIndex[address(token)] = i;
                numberOfTokens = numberOfTokens + 1;
            } catch {
                break;
            }
        }
        // Get nUSD from this pool
        (, , , , , , address lpToken) = ISynapse(pool).swapStorage();
        isPoolToken[lpToken] = true;
        numberOfTokens = numberOfTokens + 1;
        tokenIndex[lpToken] = numberOfTokens;
    }

    function setAllowances() public override onlyOwner {}

    function _approveIfNeeded(address _tokenIn, uint256 _amount)
        internal
        override
    {
        uint256 allowance = IERC20(_tokenIn).allowance(address(this), pool);
        if (allowance < _amount) {
            IERC20(_tokenIn).safeApprove(pool, UINT_MAX);
        }
    }

    function _isPaused() internal view returns (bool) {
        return ISynapse(pool).paused();
    }

    function _query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view override returns (uint256) {
        if (
            _amountIn == 0 ||
            _tokenIn == _tokenOut ||
            !isPoolToken[_tokenIn] ||
            !isPoolToken[_tokenOut] ||
            _isPaused()
        ) {
            return 0;
        }
        if (tokenIndex[_tokenIn] != numberOfTokens && tokenIndex[_tokenOut] != numberOfTokens) {
            try
                ISynapse(pool).calculateSwap(
                    tokenIndex[_tokenIn],
                    tokenIndex[_tokenOut],
                    _amountIn
                )
            returns (uint256 amountOut) {
                return amountOut.mul(poolFeeCompliment) / bips;
            } catch {
                return 0;
            }
        } else {
            if (tokenIndex[_tokenOut] == numberOfTokens) {
                uint256[] memory amounts = new uint256[](3);
                amounts[(tokenIndex[_tokenIn])] = _amountIn;
                try ISynapse(pool).calculateTokenAmount(amounts, true) returns (
                    uint256 amountOut
                ) {
                    return amountOut.mul(poolFeeCompliment) / bips;
                } catch {
                    return 0;
                }
            } else if (tokenIndex[_tokenIn] == numberOfTokens) {
                // remove liquidity
                try
                    ISynapse(pool).calculateRemoveLiquidityOneToken(
                        _amountIn,
                        tokenIndex[_tokenOut]
                    )
                returns (uint256 amountOut) {
                    return amountOut.mul(poolFeeCompliment) / bips;
                } catch {
                    return 0;
                }
            } else {
                return 0;
            }
        }
    }

    function _swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _tokenIn,
        address _tokenOut,
        address _to
    ) internal override {
        if (tokenIndex[_tokenIn] != numberOfTokens && tokenIndex[_tokenOut] != numberOfTokens) {
            ISynapse(pool).swap(
                tokenIndex[_tokenIn],
                tokenIndex[_tokenOut],
                _amountIn,
                _amountOut,
                block.timestamp
            );
            // Confidently transfer amount-out
            _returnTo(_tokenOut, _amountOut, _to);
        } else {
            // add liquidity
            if (tokenIndex[_tokenOut] == numberOfTokens) {
                uint256[] memory amounts = new uint256[](3);
                amounts[(tokenIndex[_tokenIn])] = _amountIn;

                ISynapse(pool).addLiquidity(
                    amounts,
                    _amountOut,
                    block.timestamp
                );
                _returnTo(_tokenOut, _amountOut, _to);
            }
            if (tokenIndex[_tokenIn] == numberOfTokens) {
                // remove liquidity
                ISynapse(pool).removeLiquidityOneToken(
                    _amountIn,
                    tokenIndex[_tokenOut],
                    _amountOut,
                    block.timestamp
                );
                _returnTo(_tokenOut, _amountOut, _to);
            }
        }
    }
}

