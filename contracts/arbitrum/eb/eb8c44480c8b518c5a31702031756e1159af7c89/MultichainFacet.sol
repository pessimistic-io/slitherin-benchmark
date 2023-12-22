// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IMultichainBridge.sol";
import "./IBridge.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibPlexusUtil.sol";
import "./LibData.sol";
import "./LibDiamond.sol";
import "./Signers.sol";
import "./VerifySigEIP712.sol";

contract MultichainFacet is IBridge, ReentrancyGuard, Signers, VerifySigEIP712 {
    using SafeERC20 for IERC20;

    struct Storage {
        mapping(address => address) anyTokenAddress;
        mapping(address => address) kavaAnyToken;
        mapping(address => bool) allowedRouter;
        address dev;
    }

    bytes32 internal constant NAMESPACE = keccak256("com.plexus.facets.multichain");

    function setDev(address _dev) external {
        Storage storage s = getStorage();
        require(msg.sender == LibDiamond.contractOwner(), "no entry");
        s.dev = _dev;
    }

    function initMultichain(address[] calldata routers) external {
        Storage storage s = getStorage();
        require(msg.sender == s.dev || msg.sender == LibDiamond.contractOwner());

        uint256 len = routers.length;
        for (uint256 i; i < len; ) {
            if (routers[i] == address(0)) {
                revert();
            }
            s.allowedRouter[routers[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    function viewMapping(address tokenAddress) external view returns (address) {
        Storage storage s = getStorage();
        return s.anyTokenAddress[tokenAddress];
    }

    function viewKavaMapping(address tokenAddress) external view returns (address) {
        Storage storage s = getStorage();
        return s.kavaAnyToken[tokenAddress];
    }

    function routerCheck(address router) external view returns (bool) {
        Storage storage s = getStorage();
        return s.allowedRouter[router];
    }

    function updateAddressMapping(AnyMapping[] calldata mappings) external {
        Storage storage s = getStorage();

        require(msg.sender == s.dev || msg.sender == LibDiamond.contractOwner());

        for (uint64 i; i < mappings.length; i++) {
            s.anyTokenAddress[mappings[i].tokenAddress] = mappings[i].anyTokenAddress;
        }
    }

    function updateKavaAddressMapping(AnyMapping[] calldata mappings) external {
        Storage storage s = getStorage();
        require(msg.sender == s.dev || msg.sender == LibDiamond.contractOwner());

        for (uint64 i; i < mappings.length; i++) {
            s.kavaAnyToken[mappings[i].tokenAddress] = mappings[i].anyTokenAddress;
        }
    }

    function bridgeToMultichain(BridgeData memory _bridgeData, MultiChainData calldata _multiChainData) public payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_bridgeData.srcToken, _bridgeData.amount);
        _multiChainBridgeStart(_bridgeData, _multiChainData);
    }

    function swapAndBridgeToMultichain(
        SwapData calldata _swap,
        BridgeData memory _bridgeData,
        MultiChainData calldata _multiChainData
    ) external payable nonReentrant {
        _bridgeData.amount = LibPlexusUtil._fee(_bridgeData.srcToken, LibPlexusUtil._tokenDepositAndSwap(_swap));
        _multiChainBridgeStart(_bridgeData, _multiChainData);
    }

    function _multiChainBridgeStart(BridgeData memory _bridgeData, MultiChainData calldata _multiChainData) internal {
        Storage storage s = getStorage();
        if (!s.allowedRouter[_multiChainData.router]) revert();
        address anyToken;
        if (_bridgeData.dstChainId == 2222) {
            anyToken = s.kavaAnyToken[_bridgeData.srcToken];
        } else {
            anyToken = s.anyTokenAddress[_bridgeData.srcToken];
        }

        if (_bridgeData.srcToken == anyToken) {
            if (block.chainid == 2222) {
                IMultichainBridge(_multiChainData.router).anySwapOut(anyToken, _bridgeData.recipient, _bridgeData.amount, _bridgeData.dstChainId);
            } else {
                IMultichainBridge(_multiChainData.router).Swapout(_bridgeData.amount, _bridgeData.recipient);
            }
        } else if (LibPlexusUtil._isNative(_bridgeData.srcToken)) {
            IMultichainBridge(_multiChainData.router).anySwapOutNative{value: _bridgeData.amount}(
                anyToken,
                _bridgeData.recipient,
                _bridgeData.dstChainId
            );
        } else {
            IERC20(_bridgeData.srcToken).safeApprove(_multiChainData.router, _bridgeData.amount);
            IMultichainBridge(_multiChainData.router).anySwapOutUnderlying(
                anyToken != address(0) ? anyToken : _bridgeData.srcToken,
                _bridgeData.recipient,
                _bridgeData.amount,
                _bridgeData.dstChainId
            );
            IERC20(_bridgeData.srcToken).safeApprove(_multiChainData.router, 0);
        }

        emit LibData.Bridge(_bridgeData.recipient, _bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.amount, _bridgeData.plexusData);
    }

    /// @dev fetch local storage
    function getStorage() private pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}

