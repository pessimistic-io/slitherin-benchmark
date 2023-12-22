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
import "./NonBlockingReceiver.sol";

contract OmniMfersARBI is ERC721A, Ownable, NonblockingReceiver {
    bool public saleEnabled;
    string public metadataBaseURL;
    string public PROVENANCE;

    uint256 public MAX_TXN = 2;
    uint256 public constant MAX_SUPPLY = 555;

    uint gasForDestinationLzReceive = 350000;

    constructor() ERC721A("OmniMfers", "OMFERS", MAX_TXN) {
        saleEnabled = false;
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

    function _LzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) override internal {
        // decode
        (address toAddr, uint tokenId) = abi.decode(_payload, (address, uint));

        // mint the tokens back into existence on destination chain
        _safeMint(toAddr, tokenId);
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
        require(numOfTokens <= MAX_TXN, "Cant mint more than 3");
        require(numOfTokens > 0, "Must mint at least 1 token");

        _safeMint(msg.sender, numOfTokens);
    }

    function donate() external payable {
        // feel free to donate :)
    }

    function traverseChains(uint16 _chainId, uint tokenId) public payable {
        require(msg.sender == ownerOf(tokenId), "You must own the token.");
        require(trustedRemoteLookup[_chainId].length > 0, "Unable to transfer to chain.");

        // burn NFT from current chain
        _burn(tokenId);

        // abi.encode the payload with the values to send
        bytes memory payload = abi.encode(msg.sender, tokenId);

        // encode adapterParams to specify more gas for the destination
        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint messageFee, ) = endpoint.estimateFees(_chainId, address(this), payload, false, adapterParams);
        
        require(msg.value >= messageFee, "GG: msg.value not enough to cover messageFee. Send gas for message fees");

        endpoint.send{value: msg.value}(
            _chainId,                           // destination chainId
            trustedRemoteLookup[_chainId],      // destination address of nft contract
            payload,                            // abi.encoded()'ed bytes
            payable(msg.sender),                // refund address
            address(0x0),                       // 'zroPaymentAddress' unused for this
            adapterParams                       // txParameters 
        );
    } 
}
