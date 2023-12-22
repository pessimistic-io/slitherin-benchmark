// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ONFT721.sol";

/// @title Interface of the UniversalONFT standard
contract LayerSyncONFT is ONFT721 {
    string public magicURI;
    uint256 public mintPrice;
    uint256 public nextMintId;
    uint256 public maxMintId;

    bool public isReveal;

    /// @notice Constructor for the UniversalONFT
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _startMintId the starting mint number on this chain
    /// @param _endMintId the max number of mints on this chain
    constructor(
        string memory _name, 
        string memory _symbol, 
        uint256 _minGasToTransfer, 
        address _layerZeroEndpoint, 
        uint256 _startMintId, 
        uint256 _endMintId
    ) ONFT721 (_name, _symbol, _minGasToTransfer, _layerZeroEndpoint) {
        nextMintId = _startMintId;
        maxMintId = _endMintId;
    }

    // Configuration Functions
    function setMagicURI(string memory _magicURI) external onlyOwner {
        magicURI = _magicURI;
    }

    function setReveal() external onlyOwner {
        isReveal = !isReveal;
    }

    function setPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
    }

    // Minting Function
    function mint() external payable {
        require(msg.value >= mintPrice, "Not enough ether sent");
        require(nextMintId <= maxMintId, "LayerSyncONFT: max mint limit reached");

        uint256 newId = nextMintId;
        nextMintId++;

        _safeMint(msg.sender, newId);
    }

    // Bridge Functions
    function estimateGasBridgeFee(uint16 _dstChainId, bool _useZro, bytes memory _adapterParams) public view virtual returns (uint nativeFee, uint zroFee) {
        bytes memory payload = abi.encode(msg.sender,0);
        return lzEndpoint.estimateFees(_dstChainId, payable(address(this)), payload, _useZro, _adapterParams);
    }

    function bridgeGas(uint16 _dstChainId, address _zroPaymentAddress, bytes memory _adapterParams) public payable {
        _checkGasLimit(_dstChainId, FUNCTION_TYPE_SEND, _adapterParams, dstChainIdToTransferGas[_dstChainId]);
        _lzSend(_dstChainId, abi.encode(msg.sender,0), payable(address(this)), _zroPaymentAddress, _adapterParams, msg.value);
    }

    // Token Information Functions
    function _baseURI() internal view virtual override returns (string memory) {
        if  (isReveal) {
        return magicURI;
        } else {
        return "";
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory baseTokenURI = super.tokenURI(tokenId);
        return bytes(baseTokenURI).length > 0 ? baseTokenURI : magicURI;
    }

    // Withdrawal Functions
    function withdrawFees() external onlyOwner {
        require(address(this).balance > 0, "No fees to withdraw");
        payable(owner()).transfer(address(this).balance);
    }
}

