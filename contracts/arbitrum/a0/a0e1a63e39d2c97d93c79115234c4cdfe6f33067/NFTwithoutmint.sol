// SPDX-License-Identifier: MIT
import "./Ownable.sol";
import "./ERC721Burnable.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./SafeMath.sol";
import "./IERC2981.sol";
import "./ERC20_IERC20.sol";
import "./Pausable.sol";
import "./NonblockingReceiver.sol";
import "./ClampedRandomizer.sol";

pragma solidity ^0.8.10;

contract AcidCatsNoMint is ERC721Enumerable, ERC721URIStorage, IERC2981, Pausable, Ownable, ERC721Burnable, NonblockingReceiver, ClampedRandomizer {

    event WithdrawFees(address indexed devAddress, uint amount);
    event WithdrawWrongTokens(address indexed devAddress, address tokenAddress, uint amount);
    event WithdrawWrongNfts(address indexed devAddress, address tokenAddress, uint tokenId);
    event Migration(address indexed _to, uint indexed _tokenId);

    using SafeMath for uint;
    using Address for address;

    address public royaltyAddress = 0x7ABCD5a3f77553a87f6a98b3D49bd559ae8B8329;

    string public baseURI;
    string public baseExtension = ".json";

    // VARIABLES
    uint public maxSupply = 3333;
    uint private gasForDestinationLzReceive = 350000;

    uint public royalty = 600;

    constructor(
        address _lzEndpoint
    ) ERC721("Acid Cats", "ACDC") ClampedRandomizer(maxSupply) {
        endpoint = ILayerZeroEndpoint(_lzEndpoint);
        _pause();
    }

    // This function transfers the nft from your address on the
    // source chain to the same address on the destination chain
    function traverseChains(uint16 _chainId, uint tokenId) public payable {
        require(msg.sender == ownerOf(tokenId), "You must own the token to traverse");
        require(trustedRemoteLookup[_chainId].length > 0, "This chain is currently unavailable for travel");

        // burn NFT, eliminating it from circulation on src chain
        _burn(tokenId);

        // abi.encode() the payload with the values to send
        bytes memory payload = abi.encode(msg.sender, tokenId);

        // encode adapterParams to specify more gas for the destination
        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint messageFee, ) = endpoint.estimateFees(_chainId, address(this), payload, false, adapterParams);

        require(msg.value >= messageFee, "Error: msg.value not enough to cover messageFee. Send gas for message fees");

        endpoint.send{value: msg.value}(
            _chainId, // destination chainId
            trustedRemoteLookup[_chainId], // destination address of nft contract
            payload, // abi.encoded()'ed bytes
            payable(msg.sender), // refund address
            address(0x0), // 'zroPaymentAddress' unused for this
            adapterParams // txParameters
        );
    }

    // just in case this fixed variable limits us from future integrations
    function setGasForDestinationLzReceive(uint newVal) external onlyOwner {
        gasForDestinationLzReceive = newVal;
    }

    function _LzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        // decode
        (address toAddr, uint tokenId) = abi.decode(_payload, (address, uint));

        // mint the tokens back into existence on destination chain
        _safeMint(toAddr, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }


    function tokenURI(uint tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function Owned(address _owner) external view returns (uint[] memory) {
        uint tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            return new uint[](0);
        } else {
            uint[] memory result = new uint[](tokenCount);
            uint index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function tokenExists(uint _id) external view returns (bool) {
        return (_exists(_id));
    }

    function royaltyInfo(uint, uint _salePrice) external view override returns (address receiver, uint royaltyAmount) {
        return (royaltyAddress, (_salePrice * royalty) / 10000);
    }

    //dev
    function updatePausedStatus() external onlyOwner {
        paused() ? _unpause() : _pause();
    }



    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    function setURI(uint tokenId, string memory uri) external onlyOwner {
        _setTokenURI(tokenId, uri);
    }

    function setRoyalty(uint16 _royalty) external onlyOwner {
        require(_royalty >= 0, "Royalty must be greater than or equal to 0%");
        require(_royalty <= 750, "Royalty must be greater than or equal to 7,5%");
        royalty = _royalty;
    }

    function setRoyaltyAddress(address _royaltyAddress) external onlyOwner {
        royaltyAddress = _royaltyAddress;
    }


    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    /// @dev emergency withdraw contract balance to the contract owner
    function emergencyWithdraw() external onlyOwner {
        uint amount = address(this).balance;
        require(amount > 0, "Error: no fees :(");
        payable(msg.sender).transfer(amount);
        emit WithdrawFees(msg.sender, amount);
    }

    /// @dev withdraw ERC20 tokens
    function withdrawTokens(address _tokenContract) external onlyOwner {
        IERC20 tokenContract = IERC20(_tokenContract);
        uint _amount = tokenContract.balanceOf(address(this));
        tokenContract.transfer(owner(), _amount);
        emit WithdrawWrongTokens(msg.sender, _tokenContract, _amount);
    }

    /// @dev withdraw ERC721 tokens to the contract owner
    function withdrawNFT(address _tokenContract, uint[] memory _id) external onlyOwner {
        IERC721 tokenContract = IERC721(_tokenContract);
        for (uint i = 0; i < _id.length; i++) {
            tokenContract.safeTransferFrom(address(this), owner(), _id[i]);
            emit WithdrawWrongNfts(msg.sender, _tokenContract, _id[i]);
        }
    }
}

