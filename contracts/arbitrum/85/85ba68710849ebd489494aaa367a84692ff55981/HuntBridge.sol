// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC1155.sol";
import "./IERC721.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";

import "./IHuntGame.sol";
import "./IHuntBridge.sol";
import "./ILayerZeroNonBlockingReceiver.sol";
import "./ILayerZeroUserApplicationConfig.sol";
import "./ILayerZeroEndpoint.sol";
import "./IHuntNFTFactory.sol";
import "./Consts.sol";
import "./GlobalNftERC721.sol";
import { GlobalERC1155 } from "./GlobalERC1155.sol";
import "./GlobalNftDeployer.sol";

contract HuntBridge is
    OwnableUpgradeable,
    GlobalNftDeployer,
    ERC721Holder,
    ERC1155Holder,
    IHuntBridge,
    ILayerZeroNonBlockingReceiver,
    ILayerZeroUserApplicationConfig
{
    ILayerZeroEndpoint public endpoint;
    IHuntNFTFactory private huntfactory;

    mapping(uint16 => address) public override getSubBridgeByLzId;
    //// lz id
    mapping(uint64 => uint16) public override getLzIdByChainId;

    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    struct BridgeParam {
        uint64 chainId;
        bool isErc1155;
        address addr;
        uint256 tokenId;
        address from;
        address recipient;
        bytes extraData;
    }
    BridgeParam tempBridgeParam;

    function initialize(
        address _endpoint,
        address _huntfactory,
        address _beacon721,
        address _beacon1155
    ) public initializer {
        __Ownable_init();
        endpoint = ILayerZeroEndpoint(_endpoint);
        huntfactory = IHuntNFTFactory(_huntfactory);
        beacon721 = _beacon721;
        beacon1155 = _beacon1155;

        // register lz id

        //        // testnet
        //        getLzIdByChainId[5] = 10121; // goerli
        //        getLzIdByChainId[421613] = 10143; // arb-goerli
        //        getLzIdByChainId[80001] = 10109; // mumbai
        //        getLzIdByChainId[420] = 10132; // op goerli
        //        getLzIdByChainId[84531] = 10160; // base goerli
        // mainnet
        getLzIdByChainId[1] = 101; // ethereum
        getLzIdByChainId[42161] = 110; // arb
        getLzIdByChainId[137] = 109; // polygon
        getLzIdByChainId[10] = 111; // op
        getLzIdByChainId[8453] = 184; // base
    }

    modifier selfPermit() {
        require(msg.sender == address(this));
        _;
    }

    function lzReceive(
        uint16 _lzSrcId,
        bytes calldata _pathData,
        uint64 _nonce,
        bytes calldata _payload
    ) public override {
        require(msg.sender == address(endpoint));
        require(
            _pathData.length == 40 &&
                uint160(bytes20(_pathData)) > 0 &&
                address(bytes20(_pathData)) == getSubBridgeByLzId[_lzSrcId],
            "SENDER_ERR"
        );
        require(_payload.length > 1, "PAYLOAD_ERR");

        try this.nonblockingLzReceive{ gas: gasleft() - 6e4 }(_lzSrcId, _pathData, _nonce, _payload) {} catch Error(
            string memory reason
        ) {
            _storeFailedMessage(_lzSrcId, _pathData, _nonce, _payload, bytes(reason));
        } catch (bytes memory reason) {
            _storeFailedMessage(_lzSrcId, _pathData, _nonce, _payload, reason);
        }
    }

    function retryMessage(uint16 _lzSrcId, bytes calldata _pathData, uint64 _nonce, bytes calldata _payload) public {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[_lzSrcId][_pathData][_nonce];
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
        // clear the stored message
        delete failedMessages[_lzSrcId][_pathData][_nonce];
        // execute the message. revert if it fails again
        this.nonblockingLzReceive(_lzSrcId, _pathData, _nonce, _payload);
        emit RetryMessageSuccess(_lzSrcId, _pathData, _nonce, payloadHash);
    }

    function revokeMessage(
        uint16 _lzSrcId,
        bytes calldata _pathData,
        uint64 _nonce,
        bytes calldata _payload
    ) public payable {
        // assert there is message to revoke
        bytes32 payloadHash = failedMessages[_lzSrcId][_pathData][_nonce];
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
        // clear the stored message
        delete failedMessages[_lzSrcId][_pathData][_nonce];

        (uint64 chainId, bool isERC1155, address addr, uint256 tokenId, address from, , ) = Types.decodeNftBridgeParams(
            _payload
        );
        /// @dev only happens when it is a malicious nft
        //        try IERC721(calcAddr(chainId, addr)).ownerOf(tokenId) {
        //            revert("nft owned");
        //        } catch (bytes memory) {}
        _withdraw(chainId, isERC1155, addr, tokenId, from, from, payable(msg.sender));
        emit RevokeMessageSuccess(_lzSrcId, _pathData, _nonce, payloadHash);
    }

    // @notice should calc global nft by provided info, other than trust received global nft
    function withdraw(
        uint64 originChain,
        address addr,
        uint256 tokenId,
        address recipient,
        address payable refund
    ) public payable {
        address globalNft = calcAddr(originChain, addr);
        bool isERC1155 = IGlobalNft(globalNft).originIsERC1155();
        if (isERC1155) {
            IERC1155(globalNft).safeTransferFrom(msg.sender, address(this), tokenId, 1, "");
        } else {
            IERC721(globalNft).transferFrom(msg.sender, address(this), tokenId);
        }
        _burn(address(this), originChain, addr, tokenId);
        _withdraw(originChain, isERC1155, addr, tokenId, msg.sender, recipient, refund);
    }

    /// @notice only owner
    function setSubBridgeInfo(uint64[] calldata _originChains, address[] calldata _addrs) public onlyOwner {
        require(_originChains.length == _addrs.length);
        for (uint i = 0; i < _originChains.length; i++) {
            uint16 lzid = getLzIdByChainId[_originChains[i]];
            require(lzid > 0, "no lzId");
            getSubBridgeByLzId[lzid] = _addrs[i];
        }
        emit SubBridgeInfoChanged(_originChains, _addrs);
    }

    function estimateFees(uint64 _dstChainId) public view returns (uint256) {
        (uint256 native, ) = endpoint.estimateFees(
            getLzIdByChainId[_dstChainId],
            address(this),
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            false,
            ""
        );
        return native;
    }

    ///set config
    // generic config for user Application
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) public override onlyOwner {
        endpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) public override onlyOwner {
        endpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) public override onlyOwner {
        endpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) public override onlyOwner {
        endpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    ///dao
    function setLzId(uint64 _chainId, uint16 _lzId) public onlyOwner {
        getLzIdByChainId[_chainId] = _lzId;
    }

    function setBeacon1155(address _beacon1155) public onlyOwner {
        beacon1155 = _beacon1155;
    }

    /// @notice used for internal
    function nonblockingLzReceive(uint16, bytes calldata, uint64 _nonce, bytes calldata _payload) public selfPermit {
        {
            uint64[1] memory _nonces = [_nonce]; // store in memory to avoid stack too deep
            (
                uint64 chainId,
                bool isErc1155,
                address addr,
                uint256 tokenId,
                address from,
                address recipient,
                bytes memory extraData
            ) = Types.decodeNftBridgeParams(_payload);
            tempBridgeParam = BridgeParam(chainId, isErc1155, addr, tokenId, from, recipient, extraData);
            emit NftDepositFinalized(chainId, isErc1155, addr, tokenId, from, recipient, extraData, _nonces[0]);
        }

        if (huntfactory.isHuntGame(tempBridgeParam.recipient)) {
            _mint(
                tempBridgeParam.chainId,
                tempBridgeParam.isErc1155,
                tempBridgeParam.addr,
                tempBridgeParam.tokenId,
                tempBridgeParam.recipient
            );
            IHuntGame(tempBridgeParam.recipient).startHunt();
        } else if (tempBridgeParam.recipient == Consts.CREATE_GAME_RECIPIENT) {
            (
                IHunterValidator hunterValidator,
                uint64 totalBullets,
                uint256 bulletPrice,
                uint64 ddl,
                bytes memory registerParams
            ) = abi.decode(tempBridgeParam.extraData, (IHunterValidator, uint64, uint256, uint64, bytes));
            address _game = huntfactory.createETHHuntGame(
                tempBridgeParam.from,
                address(0),
                hunterValidator,
                tempBridgeParam.isErc1155 ? IHuntGame.NFTStandard.GlobalERC1155 : IHuntGame.NFTStandard.GlobalERC721,
                totalBullets,
                bulletPrice,
                tempBridgeParam.addr,
                tempBridgeParam.chainId,
                tempBridgeParam.tokenId,
                ddl,
                registerParams
            );
            _mint(
                tempBridgeParam.chainId,
                tempBridgeParam.isErc1155,
                tempBridgeParam.addr,
                tempBridgeParam.tokenId,
                _game
            );
            IHuntGame(_game).startHunt();
        } else {
            _mint(
                tempBridgeParam.chainId,
                tempBridgeParam.isErc1155,
                tempBridgeParam.addr,
                tempBridgeParam.tokenId,
                tempBridgeParam.recipient
            );
        }
        delete tempBridgeParam;
    }

    function _withdraw(
        uint64 originChain,
        bool isERC1155,
        address addr,
        uint256 tokenId,
        address from,
        address recipient,
        address payable refund
    ) internal {
        bytes memory _calldata = Types.encodeNftBridgeParams(
            block.chainid,
            isERC1155,
            addr,
            tokenId,
            from,
            recipient,
            ""
        );
        uint16 destLzId = getLzIdByChainId[originChain];
        endpoint.send{ value: msg.value }(
            destLzId,
            abi.encodePacked(getSubBridgeByLzId[destLzId], address(this)),
            _calldata,
            refund,
            address(0),
            ""
        );
        uint64 _nonce = endpoint.getOutboundNonce(destLzId, address(this));
        emit NftWithdrawInitialized(originChain, isERC1155, addr, tokenId, from, recipient, "", _nonce);
    }

    /// @dev  store failed message for retry message
    function _storeFailedMessage(
        uint16 _lzSrcId,
        bytes memory _pathData,
        uint64 _nonce,
        bytes memory _payload,
        bytes memory _reason
    ) internal virtual {
        failedMessages[_lzSrcId][_pathData][_nonce] = keccak256(_payload);
        emit MessageFailed(_lzSrcId, _pathData, _nonce, _payload, _reason);
    }
}

