// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./SimpleFactory.sol";
import "./BoringOwnable.sol";
import "./MultiChainAdapter.sol";
import "./MultiChainNFT.sol";
import "./IERC721.sol";

contract MultiChainSenderOrReceiver is BoringOwnable, IReceiver {
    event LogAddNewAdapter(address proxy);

    uint256 private BPS = 10_000;

    SimpleFactory public immutable factory;
    address immutable private multichainNFTMaster;

    MultiChainAdapter public adapter;
    
    mapping (IERC721 => IERC721) public cloneToOriginal;
    mapping (IERC721 => IERC721) public originalToClone;


    constructor (SimpleFactory factory_, address multichainMasterNFT, address _owner) {
        factory = factory_;
        multichainNFTMaster = multichainMasterNFT;
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function addNewAdapter (address _adapter) external onlyOwner {
        adapter = MultiChainAdapter(_adapter);
        emit LogAddNewAdapter(_adapter);
    }

    function sendNFT (IERC721 nft, uint256 id, uint256 chainId, address recipient) external payable {
        require(msg.sender == nft.ownerOf(id));
        IERC721 original = cloneToOriginal[nft];

        IAdapter.RoyaltyData memory royalty = IAdapter.RoyaltyData(address(0),0);

        if (nft.supportsInterface(0x2a55205a)) {
            uint256 rate;
            (royalty.royaltyReceiver, rate) = nft.royaltyInfo(id, BPS);
            royalty.royaltyRate = uint16(rate);
        }

        if (address(original) == address(0)) {
            nft.transferFrom(msg.sender, address(this), id);
            adapter.send{value: msg.value}(chainId, address(nft), id, nft.name(), nft.symbol(), nft.tokenURI(id), recipient,  royalty);
        } else {
            MultiChainNFT(address(nft)).burn(id);
            adapter.send{value: msg.value}(chainId, address(original), id, nft.name(), nft.symbol(), nft.tokenURI(id), recipient,  royalty);
        }
    }
    
    function receiveNFT ( address nft, string calldata name, string calldata symbol, string calldata tokenURI, uint256 tokenId, address recipient, IReceiver.RoyaltyData calldata royalty) external override {
        require(msg.sender == address(adapter));
        try IERC721(nft).ownerOf(tokenId) returns (address nftOwner) {
            assert(nftOwner == address(this));
            IERC721(nft).transferFrom(address(this), recipient, tokenId);
        } catch {
            IERC721 clone = originalToClone[IERC721(nft)];
            if(address(clone) == address(0)) {
                bytes memory data = abi.encode(name, symbol, owner, address(this));
                clone = IERC721(factory.deploy(multichainNFTMaster, data ,true));
                originalToClone[IERC721(nft)] = clone;
                cloneToOriginal[clone] = IERC721(nft);
                MultiChainNFT(address(clone)).setRoyalty(royalty.royaltyReceiver, royalty.royaltyRate);
            } 
            MultiChainNFT(address(clone)).mintWithId(recipient, tokenId, tokenURI);
        }
    }
}
