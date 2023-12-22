//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IBeetsVault.sol";
import "./Zapper.sol";

contract BeetsZapper is Zapper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant BEETS_VAULT =
        0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce;
    IBeetsVault internal constant beetsVault = IBeetsVault(BEETS_VAULT);

    // Every LP has a poolId in Beets Vault contract
    mapping(address => bytes32) lpToPoolId;
    // Default token used to swap in Beets LP (default: 0th index)
    mapping(address => uint256) lpToTokenIndex;

    constructor() Zapper() {}

    function setLpToPoolId(address _lpToken, bytes32 _vaultPoolId)
        external
        onlyOwner
    {
        lpToPoolId[_lpToken] = _vaultPoolId;
    }

    function setLpToTokenIndex(address _lpToken, uint256 _defaultTokenIndex)
        external
        onlyOwner
    {
        lpToTokenIndex[_lpToken] = _defaultTokenIndex;
    }

    function _zapToLp(
        address _fromToken,
        address _toLpToken,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) internal virtual override returns (uint256 _lpAmountOut) {
        if (msg.value > 0) {
            // If you send FTM instead of WFTM these requirements must hold.
            require(_fromToken == WFTM, "invalid-from-token");
            require(_amountIn == msg.value, "invalid-amount-in");
            // Auto-wrap FTM to WFTM
            IWFTM(WFTM).deposit{value: msg.value}();
        } else {
            IERC20(_fromToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
        }

        bytes32 _lpPoolId = lpToPoolId[_toLpToken];
        (address[] memory _tokens, , ) = beetsVault.getPoolTokens(_lpPoolId);

        address _token = _tokens[lpToTokenIndex[_toLpToken]];
        uint256 _tokenOut = _swap(_fromToken, _token, _amountIn);

        IERC20(_token).safeApprove(BEETS_VAULT, 0);
        IERC20(_token).safeApprove(BEETS_VAULT, _tokenOut);

        uint256 _lpBalanceBefore = IERC20(_toLpToken).balanceOf(address(this));

        IVault.JoinPoolRequest memory _joinPoolRequest;
        _joinPoolRequest.assets = _tokens;
        _joinPoolRequest.maxAmountsIn = new uint256[](_tokens.length);
        _joinPoolRequest.maxAmountsIn[lpToTokenIndex[_toLpToken]] = _tokenOut;
        _joinPoolRequest.userData = abi.encode(
            1,
            _joinPoolRequest.maxAmountsIn,
            1
        );

        beetsVault.joinPool(
            _lpPoolId,
            address(this),
            address(this),
            _joinPoolRequest
        );

        _lpAmountOut =
            IERC20(_toLpToken).balanceOf(address(this)) -
            _lpBalanceBefore;
        require(_lpAmountOut >= _minLpAmountOut, "slippage-rekt-you");
    }

    function _unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) internal virtual override returns (uint256 _amountOut) {
        bytes32 _lpPoolId = lpToPoolId[_fromLpToken];
        (address[] memory _tokens, , ) = beetsVault.getPoolTokens(_lpPoolId);

        IERC20(_fromLpToken).safeApprove(BEETS_VAULT, 0);
        IERC20(_fromLpToken).safeApprove(BEETS_VAULT, _amountLpIn);

        IVault.ExitPoolRequest memory _exitPoolRequest;
        _exitPoolRequest.assets = _tokens;
        _exitPoolRequest.minAmountsOut = new uint256[](_tokens.length);
        _exitPoolRequest.userData = abi.encode(1, _amountLpIn);
        _exitPoolRequest.toInternalBalance = false;

        beetsVault.exitPool(
            _lpPoolId,
            address(this),
            address(this),
            _exitPoolRequest
        );

        for (uint256 i; i < _tokens.length; i++) {
            uint256 _tokenBalance = IERC20(_tokens[i]).balanceOf(address(this));
            if (_tokenBalance > 0) _swap(_tokens[i], _toToken, _tokenBalance);
        }

        _amountOut = IERC20(_toToken).balanceOf(address(this));

        require(_amountOut >= _minAmountOut, "slippage-rekt-you");

        if (_toToken == WFTM) {
            IWFTM(WFTM).withdraw(_amountOut);

            (bool _success, ) = msg.sender.call{value: _amountOut}("");
            require(_success, "ftm-transfer-failed");
        } else {
            IERC20(_toToken).transfer(msg.sender, _amountOut);
        }
    }
}

