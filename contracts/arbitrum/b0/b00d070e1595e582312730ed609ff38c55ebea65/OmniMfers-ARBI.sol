// SPDX-License-Identifier: UNLICENSED

/*

 ██████  ███    ███ ███████ ███████ ██████  ███████ 
██    ██ ████  ████ ██      ██      ██   ██ ██      
██    ██ ██ ████ ██ █████   █████   ██████  ███████ 
██    ██ ██  ██  ██ ██      ██      ██   ██      ██ 
 ██████  ██      ██ ██      ███████ ██   ██ ███████ 
                                                                                                                                                            

*/

pragma solidity ^0.8.10;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./LayerZeroable.sol";

contract OmniMfersARBI is ERC721A, Ownable, LayerZeroable {
    bool public saleEnabled;
    string public metadataBaseURL;
    string public PROVENANCE;

    uint256 public constant START_NUM = 2780;
    uint256 public MAX_TXN = 2;
    uint256 public constant MAX_SUPPLY = 555;


    constructor(address _layerZeroEndpoint) ERC721A("OmniMfers", "OMFERS", MAX_TXN, START_NUM) {
        saleEnabled = false;
        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
    }

    function setBaseURI(string memory baseURL) external onlyOwner {
        metadataBaseURL = baseURL;
    }


    function toggleSaleStatus() external onlyOwner {
        saleEnabled = !(saleEnabled);
    }

    function setMaxTxn(uint256 _maxTxn) external onlyOwner {
        MAX_TXN = _maxTxn;
    }


    function _baseURI() internal view virtual override returns (string memory) {
        return metadataBaseURL;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) external override {
        require(msg.sender == address(layerZeroEndpoint));
        require(
            _srcAddress.length == remotes[_srcChainId].length &&
                keccak256(_srcAddress) == keccak256(remotes[_srcChainId]),
            "Invalid remote sender address. owner should call setRemote() to enable remote contract"
        );

        // Decode payload
        (address to, uint256 tokenId) = abi.decode(
            _payload,
            (address, uint256)
        );

        _safeMintSpecific(to, tokenId);
    }

    function setProvenance(string memory _provenance) external onlyOwner {
        PROVENANCE = _provenance;
    }

    function withdraw() external onlyOwner {
        uint256 _balance = address(this).balance;
        address payable _sender = payable(_msgSender());
        _sender.transfer(_balance);
    }

    function reserve(uint256 num) external onlyOwner {
        require((totalSupply() + num) <= MAX_SUPPLY, "Exceed max supply");
        _safeMint(msg.sender, num);
    }

    function freeMint(uint256 numOfTokens) external payable {
        require(saleEnabled, "Sale must be active.");
        require(totalSupply() + numOfTokens <= MAX_SUPPLY, "Exceed max supply");
        require(numOfTokens <= MAX_TXN, "Cant mint more than 2");
        require(numOfTokens > 0, "Must mint at least 1 token");

        _safeMint(msg.sender, numOfTokens);
    }

    function donate() external payable {
        // feel free to donate :)
    }

    function transferToChain(
        uint256 _tokenId,
        address _to,
        uint16 _chainId
    ) external payable {
        require(ownerOf(_tokenId) == _msgSender(), "Sender is not owner");
        require(remotes[_chainId].length > 0, "Remote not configured");

        _burn(_tokenId);

        bytes memory payload = abi.encode(_to, _tokenId);

        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(version, destGasAmount);

        (uint256 messageFee, ) = layerZeroEndpoint.estimateFees(
            _chainId,
            _bytesToAddress(remotes[_chainId]),
            payload,
            false,
            adapterParams
        );
        require(
            msg.value >= messageFee,
            "Insufficient amount to cover gas costs"
        );

        layerZeroEndpoint.send{value: msg.value}(
            _chainId,
            remotes[_chainId],
            payload,
            payable(msg.sender),
            address(0x0),
            adapterParams
        );
    }

    function estimateFee(
        uint256 _tokenId,
        address _to,
        uint16 _chainId
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        bytes memory payload = abi.encode(_to, _tokenId);

        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(version, destGasAmount);

        return
            layerZeroEndpoint.estimateFees(
                _chainId,
                _bytesToAddress(remotes[_chainId]),
                payload,
                false,
                adapterParams
            );
    }

}
