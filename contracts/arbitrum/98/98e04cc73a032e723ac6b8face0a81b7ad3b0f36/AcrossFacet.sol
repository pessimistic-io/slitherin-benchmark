// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./IERC20.sol";
import { ILiFi } from "./ILiFi.sol";
import { IAcrossRouter } from "./IAcrossRouter.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibAsset } from "./LibAsset.sol";
import { LibSwap } from "./LibSwap.sol";

contract AcrossFacet is ILiFi {
    /* ========== Storage ========== */

    bytes32 internal constant NAMESPACE = keccak256("com.lifi.facets.across");
    struct Storage {
        address acrossRouter;
        address weth;
    }

    /* ========== Types ========== */

    struct AcrossData {
        address token;
        uint256 amount;
        address recipient;
        uint64 slowRelayFeePct;
        uint64 instantRelayFeePct;
        uint64 quoteTimestamp;
    }

    /* ========== Init ========== */

    function initAcross(address _acrossRouter, address _weth) external {
        Storage storage s = getStorage();
        LibDiamond.enforceIsContractOwner();
        s.acrossRouter = _acrossRouter;
        s.weth = _weth;
    }

    /* ========== Public Bridge Functions ========== */

    /**
     * @notice Bridges tokens via Across
     * @param _lifiData data used purely for tracking and analytics
     * @param _acrossData data specific to Across
     */
    function startBridgeTokensViaAcross(LiFiData memory _lifiData, AcrossData calldata _acrossData) public payable {
        if (_acrossData.token != address(0)) {
            uint256 _fromTokenBalance = LibAsset.getOwnBalance(_acrossData.token);

            LibAsset.transferFromERC20(_acrossData.token, msg.sender, address(this), _acrossData.amount);

            require(
                LibAsset.getOwnBalance(_acrossData.token) - _fromTokenBalance == _acrossData.amount,
                "ERR_INVALID_AMOUNT"
            );
        } else {
            require(msg.value == _acrossData.amount, "ERR_INVALID_AMOUNT");
        }

        _startBridge(_acrossData);

        emit LiFiTransferStarted(
            _lifiData.transactionId,
            _lifiData.integrator,
            _lifiData.referrer,
            _lifiData.sendingAssetId,
            _lifiData.receivingAssetId,
            _lifiData.receiver,
            _lifiData.amount,
            _lifiData.destinationChainId,
            block.timestamp
        );
    }

    /**
     * @notice Performs a swap before bridging via Across
     * @param _lifiData data used purely for tracking and analytics
     * @param _swapData an array of swap related data for performing swaps before bridging
     * @param _acrossData data specific to Across
     */
    function swapAndStartBridgeTokensViaAcross(
        LiFiData memory _lifiData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossData calldata _acrossData
    ) public payable {
        if (_acrossData.token != address(0)) {
            uint256 _fromTokenBalance = LibAsset.getOwnBalance(_acrossData.token);

            // Swap
            for (uint8 i; i < _swapData.length; i++) {
                LibSwap.swap(_lifiData.transactionId, _swapData[i]);
            }

            require(
                LibAsset.getOwnBalance(_acrossData.token) - _fromTokenBalance >= _acrossData.amount,
                "ERR_INVALID_AMOUNT"
            );
        } else {
            uint256 _fromBalance = address(this).balance;

            // Swap
            for (uint8 i; i < _swapData.length; i++) {
                LibSwap.swap(_lifiData.transactionId, _swapData[i]);
            }

            require(address(this).balance - _fromBalance >= _acrossData.amount, "ERR_INVALID_AMOUNT");
        }
        _startBridge(_acrossData);

        emit LiFiTransferStarted(
            _lifiData.transactionId,
            _lifiData.integrator,
            _lifiData.referrer,
            _lifiData.sendingAssetId,
            _lifiData.receivingAssetId,
            _lifiData.receiver,
            _lifiData.amount,
            _lifiData.destinationChainId,
            block.timestamp
        );
    }

    /* ========== External Config Functions ========== */

    /**
     * @dev Changes address of Across router
     * @param _newRouter address of the new router
     */
    function changeAcrossRouter(address _newRouter) external {
        Storage storage s = getStorage();
        LibDiamond.enforceIsContractOwner();
        s.acrossRouter = _newRouter;
    }

    function changeAcrossWeth(address _weth) external {
        Storage storage s = getStorage();
        LibDiamond.enforceIsContractOwner();
        s.weth = _weth;
    }

    /* ========== Internal Functions ========== */

    /**
     * @dev Conatains the business logic for the bridge via Across
     * @param _acrossData data specific to Across
     */
    function _startBridge(AcrossData calldata _acrossData) internal {
        Storage storage s = getStorage();

        if (_acrossData.token != address(0) || _acrossData.token != s.weth) {
            // Give Anyswap approval to bridge tokens
            LibAsset.approveERC20(IERC20(_acrossData.token), s.acrossRouter, _acrossData.amount);

            IAcrossRouter(s.acrossRouter).deposit(
                _acrossData.recipient,
                _acrossData.token,
                _acrossData.amount,
                _acrossData.slowRelayFeePct,
                _acrossData.instantRelayFeePct,
                _acrossData.quoteTimestamp
            );
        } else {
            IAcrossRouter(s.acrossRouter).deposit{ value: _acrossData.amount }(
                _acrossData.recipient,
                _acrossData.token,
                _acrossData.amount,
                _acrossData.slowRelayFeePct,
                _acrossData.instantRelayFeePct,
                _acrossData.quoteTimestamp
            );
        }
    }

    function getStorage() internal pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}

