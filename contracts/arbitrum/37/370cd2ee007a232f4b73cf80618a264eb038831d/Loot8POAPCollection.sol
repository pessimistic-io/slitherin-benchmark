// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./StringUtils.sol";
import "./NonblockingLzApp.sol";
import "./ICollectionManager.sol";
import "./ILoot8POAPCollection.sol";
import "./ILoot8BurnableCollection.sol";

import "./Counters.sol";
import "./ERC721.sol";
import "./ERC721Royalty.sol";

contract Loot8POAPCollection is ERC721, ERC721Royalty, ILoot8POAPCollection, ILoot8BurnableCollection, NonblockingLzApp {

    // events for cross-chain transfers
    event CollectibleReceived(address indexed to, uint256 srcChainId, uint256 collectibleId);
    event CollectibleSent(address indexed from, uint256 destChainId, uint256 collectibleId);

    event MintingDisabled(address _collection);

    bool public transferable;
    bool public disabled;
    address public governor;
    address public trustedForwarder;
    string public contractURI;

    mapping(uint256 => string) public tokenURIs;

    // Mapping Patron Address => Token URI => boolean
    // Used to check if a token is pre-minted by patron
    mapping(address => mapping(string => bool)) public patronMintedPOAP;

    uint256 public autoTokenIdStart;
    uint256 public autoTokenIdCounter;

    constructor(
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _governor,
        address _trustedForwarder,
        address _layerZeroEndpoint,
        uint256 _autoTokenIdStart
    ) ERC721(_name, _symbol)
      NonblockingLzApp(_layerZeroEndpoint) {

        // _autoTokenIdStart = 0 for disabling auto token id minting
        if(_autoTokenIdStart > 0) {
            autoTokenIdStart = _autoTokenIdStart;
            autoTokenIdCounter = _autoTokenIdStart;
        }

        contractURI = _contractURI;
        transferable = _transferable;
        governor = _governor;
        trustedForwarder = _trustedForwarder;
    }

    /**
    * @notice Mints a token to the patron
    * @param _patron address Address of the patron
    * @param _tokenURI string tokenURI for the token to be minted
    */
    function mint(
        address _patron,
        uint256 _tokenId,
        string memory _tokenURI
    ) public virtual
    {
        require(isTrustedForwarder(msg.sender), "UNAUTHORIZED");
        require(!patronMintedPOAP[_patron][_tokenURI], "PATRON OWNS TOKEN");
        require(_tokenId > 0, "TOKEN ID SHOULD BE NON-ZERO");
        if(autoTokenIdStart > 0) {
            require(_tokenId < autoTokenIdStart, "TOKENID LIMIT BREACHED");
        }
        require(StringUtils.strlen(_tokenURI) > 0, "TOKEN URI CANNOT BE EMPTY");
        require(!disabled, "MINTING IS DISABLED");
        _setTokenURI(_tokenId, _tokenURI);
        _safeMint(_patron, _tokenId);
        patronMintedPOAP[_patron][_tokenURI] = true;
    }

    /**
     * @notice Mints next available token to the patron's address
     * @param _patron address Address of the patron
     */
    function mintNext(address _patron, string memory _tokenURI) external {
        require(!patronMintedPOAP[_patron][_tokenURI], "PATRON OWNS TOKEN");
        require(autoTokenIdStart > 0, "AUTO TOKENID MINTING DISABLED FOR THIS COLLECTION");
        require(isTrustedForwarder(msg.sender), "UNAUTHORIZED");
        require(StringUtils.strlen(_tokenURI) > 0, "TOKEN URI CANNOT BE EMPTY");
        require(!disabled, "MINTING IS DISABLED");
        _setTokenURI(autoTokenIdCounter, _tokenURI);
        _safeMint(_patron, autoTokenIdCounter);
        patronMintedPOAP[_patron][_tokenURI] = true;
        autoTokenIdCounter++;
    }

    function setContractURI(string memory _contractURI) external virtual {
        require(_msgSender() == governor, "UNAUTHORIZED");
        contractURI = _contractURI;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        _requireMinted(_tokenId);
        return tokenURIs[_tokenId];
    }

    function _setTokenURI(uint256 _tokenId, string memory _tokenURI) internal {
        tokenURIs[_tokenId] = _tokenURI;
    }

    function disableMinting() external {
        require(_msgSender() == governor, "UNAUTHORIZED");
        require(!disabled, "MINTING ALREADY DISABLED");
        disabled = true;
        emit MintingDisabled(address(this));
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721Royalty) {
        ERC721Royalty._burn(tokenId);
    }

    function burn(uint256 tokenId) external {
        require(
            (_isApprovedOrOwner(_msgSender(), tokenId)), "UNAUTHORIZED OR BURN DISABLED"
        );
        _burn(tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(transferable, "TRANSFERS ARE NOT ALLOWED");
        super._transfer(from, to, tokenId);
    }

    /* ======== LayerZero ======== */

    /**
     * @notice Used to send the collectible to another blockchain
     * @param _destinationChainId uint16 Chain ID for destination chain
     * @param _collectibleId uint256 Collectible ID for the Collectible to be transferred
    */
    function sendCollectibleToChain(
        uint16 _destinationChainId, 
        uint256 _collectibleId
    ) external virtual payable {
        require(ownerOf(_collectibleId) == _msgSender(), "SENDER NOT OWNER");

        // Burn the collectible on this chain so it can be reinstantiated on the destination chain
        _burn(_collectibleId);

        // Prepare payload to mint collectible and restore state on destination chain
        bytes memory payload = abi.encode(
                                _msgSender(), 
                                _collectibleId
                            );

        // Encode the adapterParams to require more gas for the destination function call (and LayerZero message fees)
        // You can see an example of this here: https://layerzero.gitbook.io/docs/guides/advanced/relayer-adapter-parameters
        uint16 version = 1;
        uint256 gas = 200000;
        bytes memory adapterParams = abi.encodePacked(version, gas);
        (uint256 messageFee, ) = this.estimateFees(
            _destinationChainId,
            address(this),
            payload,
            false,
            adapterParams
        );

        // Send the message to the LayerZero endpoint to initiate the Collectible transfer
        require(msg.value >= messageFee,  "NOT ENOUGH MESSAGE VALUE FOR GAS");

        _lzSend(_destinationChainId, payload, payable(msg.sender), address(0x0), adapterParams, msg.value);

        // Emit an event for transfer of Collectible to another chain
        emit CollectibleSent(_msgSender(), _destinationChainId, _collectibleId);
    }

    /*
     * @notice Receives the message from the endpoint on the destination chain to mint/remint the Collectible on this chain
     * @param _srcChainId uint16 Chain ID for source chain
     * @param _from uint256 address of the sender
     * @param _nonce uint64 Nonce
     * @param _payload bytes Data needed to restore the state of the Collectible on this chain
    */
    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _from, uint64, bytes memory _payload) internal virtual override {        
        address from;
        assembly {
            from := mload(add(_from, 20))
        }

        (address toAddress, uint256 collectibleId) = abi.decode(
            _payload,
            (address, uint256)
        );

        // Mint the Collectible on this chain
        _safeMint(toAddress, collectibleId);

        // Emit an event for reception of Collectible on destination chain
        emit CollectibleReceived(toAddress, _srcChainId, collectibleId);
    }

    /**
     * @notice Returns an estimate of cross chain fees for the message to the remote endpoint when doing a Collectible transfer
     * @param _dstChainId uint16 Chain ID for destination chain
     * @param _userApplication uint256 address of the sender UA
     * @param _payload uint64 Data needed to restore the state of the Collectible on this chain 
     * @param _payInZRO bytes 
     * @param _adapterParams bytes
    */
    function estimateFees(uint16 _dstChainId, address _userApplication, bytes calldata _payload, bool _payInZRO, bytes calldata _adapterParams) external virtual view returns (uint256 nativeFee, uint256 zroFee) {
        return
            ILayerZeroEndpoint(lzEndpoint).estimateFees(
                _dstChainId,
                _userApplication,
                _payload,
                _payInZRO,
                _adapterParams
            );
    }

    /* ========= ERC2771 ============ */
    function isTrustedForwarder(address sender) internal view returns (bool) {
        return sender == trustedForwarder;
    }

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData()
        internal
        view
        virtual
        override
        returns (bytes calldata)
    {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }

    function setTokenRoyalty(uint256 _tokenId, address _receiver, uint96 _feeNumerator) external {
        require(_msgSender() == governor, "UNAUTHORIZED");
        _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) external {
        require(_msgSender() == governor, "UNAUTHORIZED");
        _resetTokenRoyalty(tokenId);
    }

    function setDefaultRoyalty(address _receiver, uint96 _feeNumerator) external {
        require(_msgSender() == governor, "UNAUTHORIZED");
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    function deleteDefaultRoyalty() external {
        require(_msgSender() == governor, "UNAUTHORIZED");
        _deleteDefaultRoyalty();
    }

    function isValidToken(uint256 _tokenId) public view returns(bool) {
        return _exists(_tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Royalty) returns (bool) {
        return  interfaceId ==  0x01ffc9a7 || // IERC165
                interfaceId ==  0x80ac58cd || // IERC721
                interfaceId ==  0x5b5e139f || // IERC721Metadata
                interfaceId ==  0x2a55205a || // IERC2981
                interfaceId ==  0x6be058c4 || // ILoot8POAPCollection
                interfaceId ==  0x42966c68 || // ILoot8BurnableCollection
                interfaceId ==  0xf625229c;   // ILayerZeroReceiver
    }
}

