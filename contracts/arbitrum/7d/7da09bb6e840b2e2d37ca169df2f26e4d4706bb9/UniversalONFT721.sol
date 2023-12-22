// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ONFT721.sol";
import "./IFactory.sol";
import "./Initializable.sol";

/// @title Interface of the UniversalONFT standard
contract UniversalONFT721 is ONFT721, Initializable {
    uint public nextMintId;
    uint public maxMintId;
    address public factory;
    string public baseURI;
    bool public mintPaused;

    constructor(
        string memory _name,
        string memory _symbol
    ) ONFT721(_name, _symbol) {
        factory = msg.sender;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Not Factory");
        _;
    }

    function initialize(
        address _endpoint,
        uint _minGasToTransfer,
        uint _nextMintId,
        uint _maxMintId
    ) external initializer {
        nextMintId = _nextMintId;
        maxMintId = _maxMintId;
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        minGasToTransferAndStore = _minGasToTransfer;
    }

    function mintFee() public view returns (uint256) {
        return IFactory(factory).mintFee();
    }

    function bridgeFee() public view returns (uint256) {
        return IFactory(factory).bridgeFee();
    }

    function feeReceiver() public view returns (address) {
        return IFactory(factory).feeReceiver();
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);
        return bytes(baseURI).length > 0 ? baseURI : "";
    }

    /// @notice Mint your ONFT
    function mint() external payable {
        require(
            nextMintId <= maxMintId,
            "UniversalONFT721: max mint limit reached"
        );

        require(mintPaused == false, "Mint paused");

        uint newId = nextMintId;
        nextMintId++;

        _transferETH(mintFee());
        _safeMint(msg.sender, newId);
    }

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint _tokenId,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable override(IONFT721Core, ONFT721Core) {
        _transferETH(bridgeFee());

        _send(
            _from,
            _dstChainId,
            _toAddress,
            _toSingletonArray(_tokenId),
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function send(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _tokenId,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) external payable {
        sendFrom(
            msg.sender,
            _dstChainId,
            _toAddress,
            _tokenId,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function _transferETH(uint256 value) internal {
        require(msg.value >= value, "Not enough value");
        if (value != 0) {
            (bool sent, ) = feeReceiver().call{value: value}("");
            require(sent, "Failed to send Ether");
        }
    }

    function setBaseUri(string memory uri) external onlyFactory {
        baseURI = uri;
    }

    function startMint() external onlyFactory {
        mintPaused = false;
    }

    function stopMint() external onlyFactory {
        mintPaused = true;
    }
}

