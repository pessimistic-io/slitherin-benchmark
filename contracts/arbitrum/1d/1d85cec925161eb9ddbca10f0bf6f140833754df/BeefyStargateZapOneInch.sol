// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";

import "./IStargateRouter.sol";
import "./IStargatePool.sol";
import "./IWETH.sol";
import "./IBeefyVault.sol";
import "./IStrategy.sol";
import "./IERC20Extended.sol";

// Aggregator Zap compatible with all Stargate vaults. 
contract BeefyStargateZapOneInch {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    // needed addresses for zap 
    address public immutable oneInchRouter;
    address public immutable stargateRouter;
    address public immutable WETH;
    address public immutable SGETH;
    uint256 public constant minimumAmount = 1000;

    event TokenReturned(address token, uint256 amount);
    event ZapIn(address vault, address tokenIn, uint256 amountIn);
    event ZapOut(address vault, address desiredToken, uint256 mooTokenIn);

    constructor(address _oneInchRouter, address _stargateRouter, address _WETH, address _SGETH) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0);
        WETH = _WETH;
        SGETH = _SGETH;

        oneInchRouter = _oneInchRouter;
        stargateRouter = _stargateRouter;
    }

    // Zap's main functions external and public functions
    function beefInETH(address _beefyVault, bytes calldata _token0, uint256 _minAmountOut) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();
        _swapAndStake(_beefyVault, WETH, _token0, _minAmountOut);
        emit ZapIn(_beefyVault, WETH, msg.value);
    }

    function beefIn(address _beefyVault, address _inputToken, uint256 _tokenInAmount, bytes calldata _token0, uint256 _minAmountOut) public {
        require(_tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');

        IERC20(_inputToken).safeTransferFrom(msg.sender, address(this), _tokenInAmount);
        _swapAndStake(_beefyVault, _inputToken, _token0, _minAmountOut);
        emit ZapIn(_beefyVault, _inputToken, _tokenInAmount);
    }

    function beefOut(address _beefyVault, uint256 _withdrawAmount, uint256 _minAmountOut) external {
        address[] memory tokens = _beefOut(_beefyVault, _withdrawAmount, _minAmountOut);
        _returnAssets(tokens);
    }

    function beefOutAndSwap(address _beefyVault, uint256 _withdrawAmount, address _desiredToken, bytes calldata _dataToken0, uint256 _minAmountOut) external {
        (IBeefyVault vault, IStargatePool pool) = _getVaultPool(_beefyVault);
        vault.safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);
        emit ZapOut(_beefyVault, _desiredToken, _withdrawAmount);

        _removeLiquidity(address(pool), _minAmountOut);
        address[] memory tokens = new address[](2);
       
        tokens[0] = pool.token() != SGETH ? pool.token() : WETH;
        tokens[1] = _desiredToken;

        _approveTokenIfNeeded(tokens[0], address(oneInchRouter));

        _swapViaOneInch(tokens[0], _dataToken0);

        _returnAssets(tokens);
    }

    // Internal functions
    function _beefOut(address _beefyVault, uint256 _withdrawAmount, uint256 _minAmountOut) private returns (address[] memory tokens) {
        (IBeefyVault vault, IStargatePool pool) = _getVaultPool(_beefyVault);

        IERC20(_beefyVault).safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);

        _removeLiquidity(address(pool), _minAmountOut);

        tokens = new address[](1);
        tokens[0] = pool.token() != SGETH ? pool.token() : WETH;
        
        emit ZapOut(_beefyVault, address(pool), _withdrawAmount);
    }

    function _removeLiquidity(address _pool, uint256 _minAmountOut) private {
        uint256 amount = IStargateRouter(stargateRouter).instantRedeemLocal(
            IStargatePool(_pool).poolId(),
            IERC20(_pool).balanceOf(address(this)),
            address(this)
        );

        require(amount >= _minAmountOut, 'Stargate: INSUFFICIENT_OUTPUT');

        if (IStargatePool(_pool).token() == SGETH) {
            IWETH(WETH).deposit{value: amount}();
        }
    }

    function _getVaultPool(address _beefyVault) private pure returns (IBeefyVault vault, IStargatePool pool) {
        (vault, pool) = (IBeefyVault(_beefyVault), IStargatePool(vault.want()));
    }

    function _swapAndStake(address _vault, address _inputToken, bytes calldata _token0, uint256 _minAmountOut) private {
        (IBeefyVault vault, IStargatePool pool) = _getVaultPool(_vault);
        address[] memory tokens = new address[](2);
        tokens[0] = pool.token();
        tokens[1] = _inputToken;

        if (_inputToken != tokens[0] && !(_inputToken == WETH && tokens[0] == SGETH)) {
            _swapViaOneInch(_inputToken, _token0);
        }

        _approveTokenIfNeeded(tokens[0], stargateRouter);
        uint256 inputBal;
        if (tokens[0] != SGETH) {
            inputBal = IERC20(tokens[0]).balanceOf(address(this));
            IStargateRouter(stargateRouter).addLiquidity(pool.poolId(), inputBal, address(this));
        } else {
            inputBal = IERC20(WETH).balanceOf(address(this));
            IWETH(WETH).withdraw(inputBal);
            IWETH(SGETH).deposit{value: inputBal}();
            IStargateRouter(stargateRouter).addLiquidity(pool.poolId(), inputBal, address(this));
        }

        uint256 poolBal = IERC20(address(pool)).balanceOf(address(this));
        require(poolBal >= _minAmountOut, "Zap: INSUFFICIENT_ADD_LIQ_OUTPUT");

        _approveTokenIfNeeded(address(pool), address(vault));
        vault.deposit(poolBal);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        _returnAssets(tokens);
    }

    // our main swap function call. we call the aggregator contract with our fed data. if we get an error we revert and return the error result. 
    function _swapViaOneInch(address _inputToken, bytes memory _callData) private {
        
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
    }

    function _returnAssets(address[] memory _tokens) private {
        uint256 balance;
        for (uint256 i; i < _tokens.length; i++) {
            balance = IERC20(_tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (_tokens[i] == WETH) {
                    IWETH(WETH).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Beefy: ETH transfer failed');
                    emit TokenReturned(_tokens[i], balance);
                } else {
                    IERC20(_tokens[i]).safeTransfer(msg.sender, balance);
                    emit TokenReturned(_tokens[i], balance);
                }
            }
        }
    }

    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint).max);
        }
    }

    // Error reporting from our call to the aggrator contract when we try to swap. 
      function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        // Forward error message from call/delegatecall
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }
}
