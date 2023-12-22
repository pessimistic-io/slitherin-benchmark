// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./IVault.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC20Helpers.sol";
import "./IManagedPool.sol";
import "./FixedPoint.sol";

import "./OwnableUpgradeable.sol";

import "./IMayfairManagedPoolController.sol";

contract ProxyInvest is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using FixedPoint for uint64;

    struct ProxyParams {
        address recipient;
        address referrer;
        address controller;
        IERC20 tokenIn;
        uint256 tokenAmountIn;
        IERC20 tokenExchange;
        uint256 minTokenAmountOut;
    }

    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    event JoinedPool(
        bytes32 indexed poolId,
        address indexed recipient,
        address manager,
        address referrer,
        uint256 amountToRecipient,
        uint256 amountToManager,
        uint256 amountToReferrer
    );

    address private _swapProvider;
    IVault private _vault;
    IWETH private _WETH;
    address private _proxyTransfer;

    function initialize(IVault vault, address swapProvider) public initializer {
        __Ownable_init();
        _vault = vault;
        _swapProvider = swapProvider;
    }

    function getVault() external view returns (IVault) {
        return _vault;
    }

    function getSwapProvider() external view returns (address) {
        return _swapProvider;
    }

    function getWETH() external view returns (IWETH) {
        return _WETH;
    }

    function getProxyTransfer() external view returns (address) {
        return _proxyTransfer;
    }

    function setProxyTransfer(address proxyTransfer) external onlyOwner {
        _proxyTransfer = proxyTransfer;
    }

    function setSwapProvider(address swapProvider) external onlyOwner {
        _swapProvider = swapProvider;
    }

    function setVault(IVault vault) external onlyOwner {
        _vault = vault;
    }

    function setWETH(IWETH weth) external onlyOwner {
        _WETH = weth;
    }

    function joinPoolExactTokenInWithSwap(
        ProxyParams calldata params,
        bytes[] calldata data
    )
        external
        payable
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        _require(
            IMayfairManagedPoolController(params.controller).isAllowedAddress(msg.sender),
            Errors.SENDER_NOT_ALLOWED
        );

        if (msg.value == 0) {
            params.tokenIn.safeTransferFrom(msg.sender, address(this), params.tokenAmountIn);
            if (params.tokenIn.allowance(address(this), _proxyTransfer) < params.tokenAmountIn) {
                params.tokenIn.safeApprove(_proxyTransfer, type(uint256).max);
            }
        } else {
            _require(
                msg.value == params.tokenAmountIn && address(params.tokenIn) == address(_WETH),
                Errors.INSUFFICIENT_ETH
            );
            _WETH.deposit{ value: msg.value }();
        }

        {
            bool success;
            bytes memory response;
            uint256 size = data.length;
            for (uint i = 0; i < size; i++) {
                (success, response) = address(_swapProvider).call(data[i]);
                if (!success) {
                    assembly {
                        let ptr := mload(0x40)
                        let _size := returndatasize()
                        returndatacopy(ptr, 0, size)
                        revert(ptr, _size)
                    }
                }
            }
        }

        uint256[] memory maxAmountsInWithBPT;
        uint256[] memory maxAmountsIn;
        IERC20[] memory tokens;
        {
            (tokens, , ) = _vault.getPoolTokens(
                IManagedPool(IMayfairManagedPoolController(params.controller).pool()).getPoolId()
            );

            uint256 size = tokens.length;
            maxAmountsInWithBPT = new uint256[](size);
            maxAmountsIn = new uint256[](size - 1);
            for (uint i = 1; i < size; i++) {
                uint256 sendAmount = tokens[i].balanceOf(address(this));
                if (sendAmount > 0) {
                    maxAmountsInWithBPT[i] = sendAmount;
                    maxAmountsIn[i - 1] = sendAmount;
                    if (tokens[i].allowance(address(this), address(_vault)) < sendAmount) {
                        tokens[i].safeApprove(address(_vault), type(uint256).max);
                    }
                }
            }
        }

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: maxAmountsInWithBPT,
            userData: abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmountsIn, params.minTokenAmountOut),
            fromInternalBalance: false
        });

        return
            _joinPool(
                params.recipient,
                params.referrer,
                params.controller,
                IMayfairManagedPoolController(params.controller).pool(),
                request
            );
    }

    function joinPool(
        address recipient,
        address referrer,
        address controller,
        IVault.JoinPoolRequest memory request
    )
        external
        payable
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        address _pool = IMayfairManagedPoolController(controller).pool();
        _require(IMayfairManagedPoolController(controller).isAllowedAddress(msg.sender), Errors.SENDER_NOT_ALLOWED);

        for (uint i = 1; i < request.assets.length; i++) {
            IERC20 tokenIn = IERC20(address(request.assets[i]));
            uint256 tokenAmountIn = request.maxAmountsIn[i];

            if (tokenAmountIn == 0 || address(tokenIn) == address(0)) continue;

            tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmountIn);
            if (tokenIn.allowance(address(this), address(_vault)) < request.maxAmountsIn[i]) {
                tokenIn.safeApprove(address(_vault), type(uint256).max);
            }
        }

        return _joinPool(recipient, referrer, controller, _pool, request);
    }

    function _joinPool(
        address recipient,
        address referrer,
        address controller,
        address pool,
        IVault.JoinPoolRequest memory request
    )
        private
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        JoinKind joinKind = abi.decode(request.userData, (JoinKind));
        bytes32 poolId = IManagedPool(pool).getPoolId();
        IERC20 poolToken = IERC20(pool);

        if (joinKind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            return _joinPoolExactIn(poolId, recipient, referrer, controller, poolToken, request);
        } else if (joinKind == JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT) {
            return _joinPoolExactOut(poolId, recipient, referrer, controller, poolToken, request);
        } else if (joinKind == JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT) {
            return _joinPoolAllTokensExactOut(poolId, recipient, referrer, controller, poolToken, request);
        }
    }

    function _joinPoolExactIn(
        bytes32 poolId,
        address recipient,
        address referrer,
        address controller,
        IERC20 poolToken,
        IVault.JoinPoolRequest memory request
    )
        private
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        address manager = IMayfairManagedPoolController(controller).getManager();
        {
            (, , uint256 minBPTAmountOut) = abi.decode(request.userData, (uint256, uint256[], uint256));
            (uint64 feesToManager, uint64 feesToReferral) = IMayfairManagedPoolController(controller).getJoinFees();

            _vault.joinPool(poolId, address(this), address(this), request);

            uint256 amountOutBPT = poolToken.balanceOf(address(this));
            amountToManager = amountOutBPT.mulDown(feesToManager);
            amountToReferrer = amountOutBPT.mulDown(feesToReferral);
            amountToRecipient = amountOutBPT.sub(amountToManager).sub(amountToReferrer);
            _require(amountToRecipient >= minBPTAmountOut, Errors.BPT_OUT_MIN_AMOUNT);

            if (referrer == address(0)) {
                referrer = manager;
            }
        }

        emit JoinedPool(poolId, recipient, manager, referrer, amountToRecipient, amountToManager, amountToReferrer);
        poolToken.safeTransfer(recipient, amountToRecipient);
        poolToken.safeTransfer(manager, amountToManager);
        poolToken.safeTransfer(referrer, amountToReferrer);

        amountsIn = request.maxAmountsIn;
    }

    function _joinPoolExactOut(
        bytes32 poolId,
        address recipient,
        address referrer,
        address controller,
        IERC20 poolToken,
        IVault.JoinPoolRequest memory request
    )
        private
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        uint256 indexToken;
        (, amountToRecipient, indexToken) = abi.decode(request.userData, (uint256, uint256, uint256));

        uint256 bptAmount;
        {
            (uint64 feesToManager, uint64 feesToReferral) = IMayfairManagedPoolController(controller).getJoinFees();
            bptAmount = amountToRecipient.divDown(FixedPoint.ONE.sub(feesToManager).sub(feesToReferral));
            amountToReferrer = bptAmount.mulDown(feesToReferral);
            amountToManager = bptAmount.sub(amountToReferrer).sub(amountToRecipient);
        }

        request.userData = abi.encode(JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT, bptAmount, indexToken);

        _vault.joinPool(poolId, address(this), address(this), request);

        IERC20 tokenIn = IERC20(address(request.assets[indexToken + 1]));

        address manager = IMayfairManagedPoolController(controller).getManager();
        if (referrer == address(0)) {
            referrer = manager;
        }

        poolToken.safeTransfer(recipient, amountToRecipient);
        poolToken.safeTransfer(manager, amountToManager);
        poolToken.safeTransfer(referrer, amountToReferrer);
        emit JoinedPool(poolId, recipient, manager, referrer, amountToRecipient, amountToManager, amountToReferrer);

        uint256 amountGiveBack = tokenIn.balanceOf(address(this));
        amountsIn = new uint256[](request.maxAmountsIn.length);
        amountsIn[indexToken + 1] = request.maxAmountsIn[indexToken + 1].sub(amountGiveBack);
        tokenIn.safeTransfer(recipient, amountGiveBack);
    }

    function _joinPoolAllTokensExactOut(
        bytes32 poolId,
        address recipient,
        address referrer,
        address controller,
        IERC20 poolToken,
        IVault.JoinPoolRequest memory request
    )
        private
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        )
    {
        (, amountToRecipient) = abi.decode(request.userData, (uint256, uint256));

        uint256 bptAmount;
        {
            (uint64 feesToManager, uint64 feesToReferral) = IMayfairManagedPoolController(controller).getJoinFees();
            bptAmount = amountToRecipient.divDown(FixedPoint.ONE.sub(feesToManager).sub(feesToReferral));
            amountToReferrer = bptAmount.mulDown(feesToReferral);
            amountToManager = bptAmount.sub(amountToReferrer).sub(amountToRecipient);
        }

        request.userData = abi.encode(JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmount);

        _vault.joinPool(poolId, address(this), address(this), request);

        address manager = IMayfairManagedPoolController(controller).getManager();
        if (referrer == address(0)) {
            referrer = manager;
        }

        poolToken.safeTransfer(recipient, amountToRecipient);
        poolToken.safeTransfer(manager, amountToManager);
        poolToken.safeTransfer(referrer, amountToReferrer);
        emit JoinedPool(poolId, recipient, manager, referrer, amountToRecipient, amountToManager, amountToReferrer);

        amountsIn = request.maxAmountsIn;

        for (uint256 i = 1; i < request.assets.length; i++) {
            IERC20 tokenIn = IERC20(address(request.assets[i]));
            uint256 amountGiveBack = tokenIn.balanceOf(address(this));
            amountsIn[i] = request.maxAmountsIn[i].sub(amountGiveBack);
            tokenIn.safeTransfer(msg.sender, amountGiveBack);
        }
    }
}

