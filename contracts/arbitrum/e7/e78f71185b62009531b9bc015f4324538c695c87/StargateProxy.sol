// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./SafeERC20Upgradeable.sol";
import "./OnlySourceFunctionality.sol";
import "./Errors.sol";
import "./SmartApprove.sol";
import "./IRubicWhitelist.sol";

import "./IStargate.sol";
import "./IStargateETH.sol";

error DifferentAmountSpent();
error DexNotAvailable();
error CannotBridgeToSameNetwork();
error LessOrEqualsMinAmount();
error NotEnoughMsgValue();
error ZeroTokenOut();

contract StargateProxy is OnlySourceFunctionality {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IStargate public stargate;
    IStargateETH public stargateETH;
    IRubicWhitelist public whitelistRegistry;

    constructor(
        uint256 _fixedCryptoFee,
        uint256 _rubicPlatformFee,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address _admin,
        IRubicWhitelist _whitelistRegistry,
        IStargate _stargate,
        IStargateETH _stargateETH
    ) {
        if (address(_whitelistRegistry) == address(0)) {
            revert ZeroAddress();
        }

        if (address(_stargate) == address(0)) {
            revert ZeroAddress();
        }

        if (address(_stargateETH) == address(0)) {
            revert ZeroAddress();
        }

        whitelistRegistry = _whitelistRegistry;
        stargate = _stargate;
        stargateETH = _stargateETH;

        initialize(
            _fixedCryptoFee,
            _rubicPlatformFee,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _admin
        );
    }

    function initialize(
        uint256 _fixedCryptoFee,
        uint256 _rubicPlatformFee,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address _admin
    ) private initializer {
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _rubicPlatformFee,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _admin
        );
    }

    function bridge(
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        BaseCrossChainParams memory _params
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        (_params.srcInputAmount, ) = _receiveTokens(_params.srcInputToken, _params.srcInputAmount);

        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        _params.srcInputAmount = accrueTokenFees(
            _params.integrator,
            _info,
            _params.srcInputAmount,
            0,
            _params.srcInputToken
        );

        uint256 fee = accrueFixedCryptoFee(_params.integrator, _info);

        _checkParamsBeforeBridge(
            _params.srcInputToken,
            _params.srcInputAmount,
            _params.dstChainID
        );

        _bridgeTokens(
            _params.srcInputToken,
            fee,
            _params.dstChainID,
            _srcPoolId,
            _dstPoolId,
            _params.srcInputAmount,
            _params.dstMinOutputAmount,
            _params.recipient
        );

        emit RequestSent(_params, 'native:stargate');
    }

    function bridgeNative(BaseCrossChainParams memory _params)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        // msg.value - fees
        uint256 amountWithFee = accrueTokenFees(
            _params.integrator,
            _info,
            accrueFixedCryptoFee(_params.integrator, _info),
            0,
            address(0)
        );

        _checkParamsBeforeBridge(
            address(0),
            _params.srcInputAmount,
            _params.dstChainID
        );

        _bridgeNative(
            _params.dstChainID,
            amountWithFee,
            _params.srcInputAmount,
            _params.dstMinOutputAmount,
            _params.recipient
        );

        _params.srcInputToken = address(0);
        emit RequestSent(_params, 'native:stargate');
    }

    function swapAndBridge(
        address _tokenOut,
        bytes calldata _swapData,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        BaseCrossChainParams memory _params
    ) external payable nonReentrant whenNotPaused {
        uint256 tokenInBeforeSwap;
        (_params.srcInputAmount, tokenInBeforeSwap) = _receiveTokens(
            _params.srcInputToken,
            _params.srcInputAmount
        );

        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        _params.srcInputAmount = accrueTokenFees(
            _params.integrator,
            _info,
            _params.srcInputAmount,
            0,
            _params.srcInputToken
        );

        uint256 fee = accrueFixedCryptoFee(_params.integrator, _info);

        IERC20Upgradeable(_params.srcInputToken).safeApprove(_params.router, _params.srcInputAmount);

        uint256 amountOut = _performSwap(_tokenOut, _params.router, _swapData, 0);

        _amountAndAllowanceChecks(
            _params.srcInputToken,
            _params.router,
            _params.srcInputAmount,
            tokenInBeforeSwap
        );

        _checkParamsBeforeBridge(_tokenOut, amountOut, _params.dstChainID);

        if (_tokenOut == address(0)) {
            _bridgeNative(
                _params.dstChainID,
                amountOut + fee,
                amountOut,
                _params.dstMinOutputAmount,
                _params.recipient
            );
        } else {
            _bridgeTokens(
                _tokenOut,
                fee,
                _params.dstChainID,
                _srcPoolId,
                _dstPoolId,
                amountOut,
                _params.dstMinOutputAmount,
                _params.recipient
            );
        }

        emit RequestSent(_params, 'native:stargate');
    }

    function swapNativeAndBridge(
        address _tokenOut,
        bytes calldata _swapData,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        BaseCrossChainParams memory _params
    ) external payable nonReentrant whenNotPaused {
        if (_tokenOut == address(0)) {
            revert ZeroTokenOut();
        }

        IntegratorFeeInfo memory _info = integratorToFeeInfo[_params.integrator];

        uint256 amountWithFee = accrueTokenFees(
            _params.integrator,
            _info,
            accrueFixedCryptoFee(_params.integrator, _info),
            0,
            address(0)
        );

        if (amountWithFee < _params.srcInputAmount) {
            revert NotEnoughMsgValue();
        }

        uint256 amountOut = _performSwap(_tokenOut, _params.router, _swapData, _params.srcInputAmount);

        _checkParamsBeforeBridge(_tokenOut, amountOut, _params.dstChainID);

        _bridgeTokens(
            _tokenOut,
            amountWithFee - _params.srcInputAmount, // fee for the provider
            _params.dstChainID,
            _srcPoolId,
            _dstPoolId,
            amountOut,
            _params.dstMinOutputAmount,
            _params.recipient
        );

        emit RequestSent(_params, 'native:stargate');
    }

    function _checkParamsBeforeSwapOut(address _anyToken, uint256 _amount) private view {
        // initial min amount is 0
        // revert in case we received 0 tokens after swap or _receiveTokens
        if (_amount <= minTokenAmount[_anyToken]) {
            revert LessOrEqualsMinAmount();
        }
    }

    /// @dev Checks that dex spent the specified amount
    /// @dev Also erases the allowance to the dex if there is
    /// @param _tokenIn token that we swapped on dex and approved
    /// @param _router the dex address
    /// @param _amountIn amount that we should spend
    /// @param _tokenInBefore amount of token before swap
    function _amountAndAllowanceChecks(
        address _tokenIn,
        address _router,
        uint256 _amountIn,
        uint256 _tokenInBefore
    ) internal {
        // check for spent amount
        if (_tokenInBefore - IERC20Upgradeable(_tokenIn).balanceOf(address(this)) != _amountIn) {
            revert DifferentAmountSpent();
        }

        // reset allowance back to zero, just in case
        if (IERC20Upgradeable(_tokenIn).allowance(address(this), _router) > 0) {
            IERC20Upgradeable(_tokenIn).safeApprove(_router, 0);
        }
    }


    /*
     * @return Received amount after swap
     */
    function _performSwap(
        address _tokenOut,
        address _dex,
        bytes calldata _data,
        uint256 _value
    ) internal returns (uint256) {
        if (!whitelistRegistry.isWhitelistedDEX(_dex)) revert DexNotAvailable();

        bool isNativeOut = _tokenOut == address(0);

        uint256 balanceBeforeSwap = isNativeOut
            ? address(this).balance
            : IERC20Upgradeable(_tokenOut).balanceOf(address(this));

        AddressUpgradeable.functionCallWithValue(_dex, _data, _value);

        return
            isNativeOut
                ? address(this).balance - balanceBeforeSwap
                : IERC20Upgradeable(_tokenOut).balanceOf(address(this)) - balanceBeforeSwap;
    }

    function _receiveTokens(address _tokenIn, uint256 _amountIn)
        internal
        returns (uint256, uint256)
    {
        uint256 balanceBeforeTransfer = IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        IERC20Upgradeable(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        uint256 balanceAfterTransfer = IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        _amountIn = balanceAfterTransfer - balanceBeforeTransfer;
        return (_amountIn, balanceAfterTransfer);
    }

    /// @dev Calls stargate function for token bridge
    /// @param _tokenIn token address
    /// @param _fee Fee for the provider
    /// @param _dstChain Destination chain id
    /// @param _srcPoolId Provider's source pool id
    /// @param _dstPoolId Provider's destination pool id
    /// @param _amount bridging amount
    /// @param _minAmountOut Min amount to receive
    /// @param _recipient The destination recipient
    function _bridgeTokens(
        address _tokenIn,
        uint256 _fee,
        uint256 _dstChain,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint256 _amount,
        uint256 _minAmountOut,
        address _recipient
    ) private {
        IERC20Upgradeable(_tokenIn).safeApprove(address(stargate), _amount);

        stargate.swap{value: _fee}(
            uint16(_dstChain),
            _srcPoolId,
            _dstPoolId,
            payable(msg.sender),
            _amount,
            _minAmountOut,
            IStargate.lzTxObj(0, 0, "0x"),
            abi.encodePacked(_recipient),
            bytes("")
        );
    }

    /// @dev Calls stargate function for native bridge
    /// @param _dstChain Destination chain id
    /// @param _amountWithFee Total amount = amount to bridge + provider's fee
    /// @param _amountWithoutFee Amount to bridge
    /// @param _minAmountOut Min amount to receive
    /// @param _recipient The destination recipient
    function _bridgeNative(
        uint256 _dstChain,
        uint256 _amountWithFee,
        uint256 _amountWithoutFee,
        uint256 _minAmountOut,
        address _recipient
    ) private {
        stargateETH.swapETH{value: _amountWithFee}(
            uint16(_dstChain),
            payable(msg.sender),
            abi.encodePacked(_recipient),
            _amountWithoutFee,
            _minAmountOut
        );
    }

    function _checkParamsBeforeBridge(
        address _transitToken,
        uint256 _amount,
        uint256 _dstChain
    ) private view {
        // initial min amount is 0
        // revert in case we received 0 tokens after swap
        if (_amount <= minTokenAmount[_transitToken]) {
            revert LessOrEqualsMinAmount();
        }

        if (block.chainid == _dstChain) revert CannotBridgeToSameNetwork();
    }

    /// MANAGEMENT ///

    /**
     * @dev Sets the address of a new whitelist registry contract
     * @param _newWhitelistRegistry The address of the registry
     */
    function setWhitelistRegistry(IRubicWhitelist _newWhitelistRegistry) external onlyAdmin {
        if (address(_newWhitelistRegistry) == address(0)) {
            revert ZeroAddress();
        }

        whitelistRegistry = _newWhitelistRegistry;
    }
}

