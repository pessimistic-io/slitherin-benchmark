// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {VaultController, IEarthquake} from "./vaultController.sol";
import {BridgeController} from "./bridgeController.sol";
import {BytesLib} from "./BytesLib.sol";
import {UniswapV3Swapper} from "./uniswapV3.sol";
import {UniswapV2Swapper} from "./uniswapV2.sol";

import {IStargateReceiver} from "./IStargateReceiver.sol";
import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";
import {ERC1155Holder} from "./ERC1155Holder.sol";
import {IERC20} from "./IERC20.sol";

import "./console.sol";

contract ZapDest is
    Ownable,
    ERC1155Holder,
    VaultController,
    BridgeController,
    UniswapV2Swapper,
    UniswapV3Swapper,
    IStargateReceiver,
    ILayerZeroReceiver
{
    using BytesLib for bytes;
    address public immutable stargateRelayer;
    address public immutable stargateRelayerEth;
    address public immutable layerZeroRelayer;

    mapping(address => uint256) public addrCounter;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(bytes1 => address) public idToExchange;
    mapping(address => uint256) public whitelistedVault;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public receiverToVaultToIdToAmount;

    event ReceivedDeposit(address token, address receiver, uint256 amount);
    event ReceivedWithdrawal(
        bytes1 orderType,
        address receiver,
        uint256 amount
    );
    event TrustedRemoteAdded(
        uint16 chainId,
        bytes trustedAddress,
        address sender
    );
    event TokenToHopBridgeSet(
        address[] tokens,
        address[] bridges,
        address sender
    );
    event VaultWhitelisted(address vault, address sender);

    constructor(
        address _stargateRelayer,
        address _stargateRelayerEth,
        address _layerZeroRelayer,
        address celerBridge,
        address hyphenBridge,
        address uniswapV2Factory,
        address sushiSwapFactory,
        address uniswapV3Factory,
        bytes memory _primaryInitHash,
        bytes memory _secondaryInitHash
    )
        payable
        BridgeController(celerBridge, hyphenBridge)
        UniswapV2Swapper(
            uniswapV2Factory,
            sushiSwapFactory,
            _primaryInitHash,
            _secondaryInitHash
        )
        UniswapV3Swapper(uniswapV3Factory)
    {
        if (_stargateRelayer == address(0)) revert InvalidInput();
        if (_stargateRelayerEth == address(0)) revert InvalidInput();
        if (_layerZeroRelayer == address(0)) revert InvalidInput();
        stargateRelayer = _stargateRelayer;
        stargateRelayerEth = _stargateRelayerEth;
        layerZeroRelayer = _layerZeroRelayer;
    }

    //////////////////////////////////////////////
    //                 ADMIN                   //
    //////////////////////////////////////////////
    function setTrustedRemoteLookup(
        uint16 srcChainId,
        bytes calldata trustedAddress
    ) external payable onlyOwner {
        if (keccak256(trustedAddress) == keccak256(bytes("")))
            revert InvalidInput();
        trustedRemoteLookup[srcChainId] = trustedAddress;
        emit TrustedRemoteAdded(srcChainId, trustedAddress, msg.sender);
    }

    function setTokenToHopBridge(
        address[] calldata _tokens,
        address[] calldata _bridges
    ) external payable onlyOwner {
        if (_tokens.length != _bridges.length) revert InvalidInput();
        for (uint256 i = 0; i < _tokens.length; ) {
            tokenToHopBridge[_tokens[i]] = _bridges[i];
            unchecked {
                i++;
            }
        }
        emit TokenToHopBridgeSet(_tokens, _bridges, msg.sender);
    }

    function whitelistVault(address _vaultAddress) external payable onlyOwner {
        if (_vaultAddress == address(0)) revert InvalidInput();
        whitelistedVault[_vaultAddress] = 1;
        emit VaultWhitelisted(_vaultAddress, msg.sender);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////s
    /// @param _chainId The remote chainId sending the tokens
    /// @param _srcAddress The remote Bridge address
    /// @param _nonce The message ordering nonce
    /// @param _token The token contract on the local chain
    /// @param amountLD The qty of local _token contract tokens
    /// @param _payload The bytes containing the toAddress
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes calldata _payload
    ) external payable override {
        // TODO: Check the amoutnLD is the correct amount
        if (msg.sender != stargateRelayer && msg.sender != stargateRelayerEth)
            revert InvalidCaller();
        (address receiver, uint256 id, address vaultAddress) = abi.decode(
            _payload,
            (address, uint256, address)
        );

        // TODO: In the event we revert - does stargate refund? Or should we have refund addeess?
        if (whitelistedVault[vaultAddress] != 1) revert InvalidVault();

        // NOTE: We should know the epochId even when queueing
        // EpochId = uint256(keccak256(abi.encodePacked(marketId,epochBegin,epochEnd)));
        receiverToVaultToIdToAmount[receiver][vaultAddress][id] += amountLD;

        // NOTE: When payload > 96 we are signalling this is being queued for the next epoch
        if (_payload.length == 128) id = 0;
        // TODO: Hardcode address(this) as a constant
        _depositToVault(id, amountLD, address(this), _token, vaultAddress);
        emit ReceivedDeposit(_token, address(this), amountLD);
    }

    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        if (msg.sender != layerZeroRelayer) revert InvalidCaller();
        if (
            keccak256(_srcAddress) !=
            keccak256(trustedRemoteLookup[_srcChainId])
        ) revert InvalidCaller();

        address fromAddress;
        assembly {
            fromAddress := mload(add(_srcAddress, 20))
        }
        // TODO: Iterate the addrCounter - suggested by LZ?
        unchecked {
            addrCounter[fromAddress] += 1;
        }

        // NOTE: Decoding data and slicing payload for swapPayload
        (
            bytes1 funcSelector,
            bytes1 bridgeId,
            address receiver,
            uint256 id,
            address vaultAddress
        ) = abi.decode(_payload, (bytes1, bytes1, address, uint256, address));
        if (funcSelector == 0x00) revert InvalidFunctionId();

        _payload = _payload.length == 160
            ? bytes("")
            : _payload.sliceBytes(160, _payload.length - 160);

        _withdraw(
            funcSelector,
            bridgeId,
            receiver,
            id,
            _srcChainId,
            vaultAddress,
            _payload
        );
    }

    function withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId,
        address vaultAddress,
        bytes memory _withdrawPayload
    ) external {
        _withdraw(
            funcSelector,
            bridgeId,
            receiver,
            id,
            _srcChainId,
            vaultAddress,
            _withdrawPayload
        );
    }

    //////////////////////////////////////////////
    //                 PRIVATE                  //
    //////////////////////////////////////////////
    function _withdraw(
        bytes1 funcSelector,
        bytes1 bridgeId,
        address receiver,
        uint256 id,
        uint16 _srcChainId,
        address vaultAddress,
        bytes memory _payload
    ) private {
        if (whitelistedVault[vaultAddress] != 1) revert InvalidVault();
        uint256 assets = receiverToVaultToIdToAmount[receiver][vaultAddress][
            id
        ];
        if (assets == 0) revert NullBalance();
        delete receiverToVaultToIdToAmount[receiver][vaultAddress][id];

        // NOTE: We check FS!=0x00 (sgReceive()) && FS==0x01 && FS<4
        if (funcSelector == 0x01)
            _withdrawFromVault(id, assets, receiver, vaultAddress);
        else if (uint8(funcSelector) < 4) {
            // TODO: Hardcode address(this) as a constant
            uint256 amountReceived = _withdrawFromVault(
                id,
                assets,
                address(this),
                vaultAddress
            );
            address asset = IEarthquake(vaultAddress).asset();
            if (funcSelector == 0x03)
                // NOTE: Re-using amountReceived for bridge input
                (asset, _payload, amountReceived) = _swapToBridgeToken(
                    amountReceived,
                    asset,
                    _payload
                );
            _bridgeToSource(
                bridgeId,
                receiver,
                asset,
                amountReceived,
                _srcChainId,
                _payload
            );
        } else revert InvalidFunctionId();
        emit ReceivedWithdrawal(funcSelector, receiver, assets);
    }

    function _swapToBridgeToken(
        uint256 swapAmount,
        address token,
        bytes memory _payload
    ) internal returns (address, bytes memory, uint256 amountOut) {
        (
            bytes1 swapId,
            uint256 toAmountMin,
            bytes1 dexId,
            address toToken
        ) = abi.decode(_payload, (bytes1, uint256, bytes1, address));

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = toToken;

        if (swapId == 0x01) {
            amountOut = _swapUniswapV2(
                dexId,
                swapAmount,
                abi.encode(path, toAmountMin) // swapPayload
            );
            _payload = _payload.sliceBytes(128, _payload.length - 128);
        } else if (swapId == 0x02) {
            uint24[] memory fee = new uint24[](1);
            (, , , , fee[0]) = abi.decode(
                _payload,
                (bytes1, uint256, bytes1, address, uint24)
            );
            amountOut = _swapUniswapV3(
                swapAmount,
                abi.encode(path, fee, toAmountMin) // swapPayload
            );
            _payload = _payload.sliceBytes(160, _payload.length - 160);
        } else revert InvalidSwapId();
        return (toToken, _payload, amountOut);
    }
}

