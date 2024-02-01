//
//
//
//                                                 #####(
//                                              ###########
//                       @@@                   ###/    ####
//                       @@@    @@@@@@&  @@@@       #######.
//          @@@@,  @@@   @@@  @@@@@@@@ @@@@@@@@          ####
//        @@@@@@@@@@@@@ @@@@@ @@@@@@@@ @@@@@@@@  ###     ####
//       @@@@#    @@@@@ @@@@@   @@@@     @@@@    ##########*
//       @@@@@    @@@@@ @@@@@   @@@@     @@@@
//        @@@@@@@@@@@@@ @@@@@   @@@@     @@@@@@
//                @@@@@  @@@    @@@       @@@@@
//        @@@@@@@@@@@@
//           &@@@@.
//
//
//
//
pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./IERC1155ReceiverUpgradeable.sol";
import "./ERC165Upgradeable.sol";
import "./Initializable.sol";

// SPDX-License-Identifier: UNLICENSED

interface ERCBase {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
  function isApprovedForAll(address account, address operator) external view returns (bool);
  function getApproved(uint256 tokenId) external view returns (address);
}

interface ERC721Partial is ERCBase {
  function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface ERC1155Partial is ERCBase {
  function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external;
}

contract Gifts is Initializable, PausableUpgradeable, OwnableUpgradeable, IERC721ReceiverUpgradeable, IERC1155ReceiverUpgradeable {

    bytes4 _ERC721;
    bytes4 _ERC1155;

    event NFTGifted(address indexed owner, address indexed tokenContractAddress, uint256 tokenId, uint indexed id, uint256 timestamp);
    event NFTClaimed(address indexed recipient, address indexed tokenContractAddress, uint256 tokenId, uint indexed id, uint256 timestamp);
    event NFTWithdrawn(address indexed owner, address indexed tokenContractAddress, uint256 tokenId, uint indexed id, uint256 timestamp);

    // CHANGE BASED ON DEPLOYED CHAIN
    uint24 constant chainId = 1;

    struct Gift {
        address sender;
        address recipient;
        uint id;
        address tokenContractAddress;
        uint256 tokenId;
        bool claimed;
        bool withdrawn;
    }

    Gift[] gifts;
    mapping (address => uint256[]) giftsSent;
    mapping (address => uint256[]) giftsReceived;

    address _giftSigner;

    uint _defaultFee;

    struct FeeOverride {
        uint fee;
        bool set;
    }

    mapping (address => FeeOverride) senderFeeOverride;
    mapping (address => FeeOverride) tokenContractFeeOverride;

    uint _amountOfGasToSendToRelay;

    function initialize() public initializer {
        _ERC721 = 0x80ac58cd;
        _ERC1155 = 0xd9b67a26;

        // Call the init function of OwnableUpgradeable to set owner
        // Calls will fail without this
        __Ownable_init();

        _defaultFee = 0.01 ether;

        //set the NFT claim signer to be the deployer of the contract.
        //this can be changed after deployment
        _giftSigner = owner();
    }

    function pause() onlyOwner external {
        _pause();
    }

    function unpause() onlyOwner external {
        _unpause();
    }

    function setGiftSigner(address newSigner) onlyOwner external {
        _giftSigner = newSigner;
    }

    function giftSigner() view public returns(address) {
        return _giftSigner;
    }

    function setDefaultFee(uint newFee) onlyOwner external {
        _defaultFee = newFee;
    }

    function getDefaultFee() public view returns (uint) {
        return _defaultFee;
    }

    function setGasToSendToRelay(uint newGasAmount) onlyOwner external {
        _amountOfGasToSendToRelay = newGasAmount;
    }

    function getGasToSendToRelay() public view returns (uint) {
        return _amountOfGasToSendToRelay;
    }

    function isSenderFeeOverride(address sender) public view returns (bool) {
        return senderFeeOverride[sender].set;
    }

    function getSenderFee(address sender) public view returns (uint) {
        return senderFeeOverride[sender].fee;
    }

    function setSenderFee(address sender, uint newFee) onlyOwner external {
        senderFeeOverride[sender] = FeeOverride(newFee, true);
    }

    function unsetSenderFee(address sender) onlyOwner external {
        delete(senderFeeOverride[sender]);
    }

    function isTokenContractFeeOverride(address tokenContractAddress) public view returns (bool) {
        return tokenContractFeeOverride[tokenContractAddress].set;
    }

    function getTokenContractFee(address tokenContractAddress) public view returns (uint) {
        return tokenContractFeeOverride[tokenContractAddress].fee;
    }

    function setTokenContractFee(address tokenContractAddress, uint newFee) onlyOwner external {
        tokenContractFeeOverride[tokenContractAddress] = FeeOverride(newFee, true);
    }

    function unsetTokenContractFee(address tokenContractAddress) onlyOwner external {
        delete(tokenContractFeeOverride[tokenContractAddress]);
    }

    function getFee(address giftSender, address tokenContractAddress) public view returns (uint) {
        uint fee = getDefaultFee();

        //METHOD 1 direct mapping access test for gas vs method 2 below
        // //if sender override
        // if(senderFeeOverride[giftSender].set == true) {
        //   if(senderFeeOverride[giftSender].fee < fee) {
        //     fee = senderFeeOverride[giftSender].fee;
        //   }
        // }
        //
        // //if nftcontract override
        // if(tokenContractFeeOverride[nftContract].set == true) {
        //   if(tokenContractFeeOverride[nftContract].fee < fee) {
        //     fee = tokenContractFeeOverride[nftContract].fee;
        //   }
        // }

        //METHOD 2 with internal functions test for gas
        //if sender override
        if(isSenderFeeOverride(giftSender) == true) {
            uint senderFee = getSenderFee(giftSender);

            if(senderFee < fee) {
                fee = senderFee;
            }
        }

        //if nftcontract override
        if(isTokenContractFeeOverride(tokenContractAddress) == true) {
            uint tokenContractFee = getTokenContractFee(tokenContractAddress);

            if(tokenContractFee < fee) {
                fee = tokenContractFee;
            }
        }

        //return the lowest number
        return fee;
    }

    function withdrawFees(address payable to) public payable onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0 wei, "Error: No balance to withdraw");
        to.transfer(balance);
    }

    function claimNFT(uint256 giftId,
                      address recipientAddress,
                      bytes32 hashedmessage,
                      uint8 sigV,
                      bytes32 sigR,
                      bytes32 sigS) external whenNotPaused {

        ERCBase tokenContract;

        bytes32 eip712DomainHash = keccak256(
            abi.encode(
                keccak256(
                    abi.encodePacked("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                ),
                keccak256("Gift3"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );

        bytes32 hashStruct = keccak256(
            abi.encode(
                keccak256(abi.encodePacked("GiftClaim(uint256 giftId,address recip_wallet)")),
                giftId,
                recipientAddress
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", eip712DomainHash, hashStruct));

        require(hash == hashedmessage, "Hashes do not match");

        address recovered_signer = ecrecover(hash, sigV, sigR, sigS);

        require(recovered_signer == giftSigner(), "Must be signed by GiftSigner");

        Gift memory gift = gifts[giftId];
        if(
            gift.claimed == false &&
            gift.withdrawn == false
        ) {
            tokenContract = ERCBase(gift.tokenContractAddress);

            if (tokenContract.supportsInterface(_ERC721)) {
                ERC721Partial(gift.tokenContractAddress).safeTransferFrom(address(this), recipientAddress, gift.tokenId);
                emit NFTClaimed(recipientAddress, gift.tokenContractAddress, gift.tokenId, giftId, block.timestamp);
            } else if(tokenContract.supportsInterface(_ERC1155)) {
                ERC1155Partial(gift.tokenContractAddress).safeTransferFrom(address(this), recipientAddress, gift.tokenId, 1, "");
                emit NFTClaimed(recipientAddress, gift.tokenContractAddress, gift.tokenId, giftId, block.timestamp);
            } else {
                revert("Token contract not ERC721 or ERC1155");
            }

            gifts[giftId].claimed = true;
            gifts[giftId].recipient = recipientAddress;
            giftsReceived[recipientAddress].push(giftId);

            return;
        }

        revert("Gift not found or already claimed or withdrawn");
    }

    function withdrawNFT(uint256 giftId) external {
        ERCBase tokenContract;

        tokenContract = ERCBase(gifts[giftId].tokenContractAddress);

        require(gifts[giftId].sender == msg.sender, "Caller must be original sender");
        require(gifts[giftId].withdrawn != true, "Gift already withdrawn");
        require(gifts[giftId].claimed != true, "Gift already claimed");

        if (tokenContract.supportsInterface(_ERC721)) {
          ERC721Partial(gifts[giftId].tokenContractAddress).safeTransferFrom(address(this), msg.sender, gifts[giftId].tokenId);
        }
        else if (tokenContract.supportsInterface(_ERC1155)) {
          ERC1155Partial(gifts[giftId].tokenContractAddress).safeTransferFrom(address(this), msg.sender, gifts[giftId].tokenId, 1, "");
        } else {
          revert("Contract is not ERC721 or ERC1155");
        }

        gifts[giftId].withdrawn = true;
        emit NFTWithdrawn(msg.sender, gifts[giftId].tokenContractAddress, gifts[giftId].tokenId, giftId, block.timestamp);
        return;
    }

    function giftNFT(address tokenContractAddress, uint256 tokenId) external payable whenNotPaused {
        require(tokenContractAddress != address(0), "Token contract cannot be 0x0");

        ERCBase tokenContract;
        tokenContract = ERCBase(tokenContractAddress);

        // load the amount of gas to split off and send to relay to fund claim txn
        uint amountOfGasToSendToRelay = getGasToSendToRelay();

        //check if enough fee has been sent in the transaction
        //this will also check for overrides for sender and contract
        //this will also check it includes the amount of gas to send to the relay for claim txn
        require(msg.value >= (getFee(msg.sender, tokenContractAddress) + amountOfGasToSendToRelay), "Transaction not including enough fee.");

        if (tokenContract.supportsInterface(_ERC721)) {
            require(
                tokenContract.getApproved(tokenId) == address(this) ||
                tokenContract.isApprovedForAll(msg.sender, address(this)),
                    "Token not yet approved for transfer");

            ERC721Partial(tokenContractAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        }
        else if (tokenContract.supportsInterface(_ERC1155)) {
            require(
                tokenContract.isApprovedForAll(msg.sender, address(this)),
                    "Token not yet approved for transfer");

            ERC1155Partial(tokenContractAddress).safeTransferFrom(msg.sender, address(this), tokenId, 1, "");
        } else {
            revert("Token contract is not ERC721 or ERC1155");
        }

        Gift memory currentGift;
        currentGift.id = gifts.length;
        currentGift.sender = msg.sender;
        currentGift.tokenContractAddress = tokenContractAddress;
        currentGift.tokenId = tokenId;
        currentGift.claimed = false;
        currentGift.withdrawn = false;
        //currentGift.block = block.number;

        gifts.push(currentGift);
        giftsSent[msg.sender].push(currentGift.id);

        //send gas to relay/signer
        address signer = giftSigner();
        payable(signer).transfer(amountOfGasToSendToRelay);

        emit NFTGifted(msg.sender, tokenContractAddress, tokenId, currentGift.id, block.timestamp);
    }

    function getGiftsSent(address giftSender) public view returns (uint[] memory) {
        return giftsSent[giftSender];
    }

    function getGiftsReceived(address giftRecipient) public view returns (uint[] memory) {
        return giftsReceived[giftRecipient];
    }

    function getGiftSender(uint giftId) public view returns (address) {
        return gifts[giftId].sender;
    }

    function getGiftRecipient(uint giftId) public view returns (address) {
        return gifts[giftId].recipient;
    }

    function getGiftTokenContractAddress(uint giftId) public view returns (address) {
        return gifts[giftId].tokenContractAddress;
    }

    function getGiftTokenId(uint giftId) public view returns (uint) {
        return gifts[giftId].tokenId;
    }

    function isGiftClaimed(uint giftId) public view returns (bool) {
        return gifts[giftId].claimed;
    }

    function isGiftWithdrawn(uint giftId) public view returns (bool) {
        return gifts[giftId].withdrawn;
    }

    /**
     * Implements ERC721 recieve support.
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * Implements ERC1155 recieve support.
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155 recieve support.
     */
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceID) external override pure returns (bool) {
        return  interfaceID == 0x80ac58cd ||    // ERC-721 support
                interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
                interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }

    receive () external payable { }

    fallback () external payable { }

}

