// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC721.sol";
import "./ERC721.sol";
import "./IERC2981.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IERC20.sol";

error PriceNotMet(address collectionAddress, uint256 tokenId, uint256 price);
error NotListed(address collectionAddress, uint256 tokenId);
error AlreadyListed(address collectionAddress, uint256 tokenId);
error NotOwner();
error NotApprovedForMarketplace();
error PriceMustBeAboveZero();

contract LazyMarketplace is ReentrancyGuard {

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // Voucher to be used at the time of Lazy Listing
    struct ListVoucher {
        uint256 price;
        uint256 tokenId;
        address collectionAddress;
        string nonce;
        string message;
    }

    // Definition of Item Listed event.
    event ItemListed (
        address indexed seller,
        address indexed collectionAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    // Definition of Item Canceled event.
    event ItemCanceled(
        address indexed seller,
        address indexed collectionAddress,
        uint256 indexed tokenId
    );

    // Definition of Item Bought event.
    event ItemBought(
        address indexed buyer,
        address indexed collectionAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    // One dimensional array mapping collection address to custom erc20 token.
    mapping(address => address) private s_collection_to_token;

    // Modifier to check if spender is the owner of the NFT.
    modifier isOwner(
        address collectionAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 collection = IERC721(collectionAddress);
        address owner = collection.ownerOf(tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

    // Function to map Collection Address with the Token Address of custom ERC20 token.
    function setTokenToCollection(
        address collectionAddress,
        address tokenAddress
    )
        external
    {
        address owner = getCollectionOwner(collectionAddress);
        require(owner == msg.sender || owner == address(0), "Only owner can set ERC20 for it's collection");
        s_collection_to_token[collectionAddress] = tokenAddress;
    }

    function getCollectionOwner(
        address collectionAddress
    )
        public
        view
        returns(address)
    {
        Ownable contractObject;
        contractObject = Ownable(collectionAddress);
        try contractObject.owner() {
            return contractObject.owner();
        } catch {
            return address(0);
        }
    }

    // Getter function for the ERC20 token mapped against a collection 
    function getTokenFromCollection(
        address collectionAddress
    )
        public
        view
        returns(address)
    {
        return s_collection_to_token[collectionAddress];
    }

    // Function to conduct purchase as per signed message
    function buyUsingSignedListing(ListVoucher calldata listingVoucher, uint8 v, bytes32 r, bytes32 s)
        external
        payable
    {
        ERC721 nftContract;
        string memory message = listingVoucher.message;
        address signer = verifyString(message, v, r, s);
        address collectionAddress = listingVoucher.collectionAddress;
        uint256 tokenId = listingVoucher.tokenId;
        uint256 price = listingVoucher.price;
        nftContract = ERC721(collectionAddress);
        address owner = nftContract.ownerOf(tokenId);
        require(owner == signer, "You are not the owner of the NFT!");
        if ( s_collection_to_token[collectionAddress] != address(0) ) {
            buyItemWithCustomToken(collectionAddress, tokenId, price);
        } else {
            buyItemWithNativeToken(collectionAddress, tokenId, price);
        }
    }

    // Check if a contract supports royalties
    function checkRoyalties(address _contract) view public returns (bool) 
    {
        (bool success) = IERC165(_contract).supportsInterface(_INTERFACE_ID_ERC2981);
        return success;
    }

    // Function to buy NFT using custom ERC20 token.
    function buyItemWithCustomToken(address collectionAddress, uint256 tokenId, uint256 priceValue)
        public
        payable
        nonReentrant
    {
        ERC721 nftContract;
        nftContract = ERC721(collectionAddress);
        address tokenAddress = s_collection_to_token[collectionAddress];
        address owner = nftContract.ownerOf(tokenId);
        bool success  = checkRoyalties(collectionAddress);
        if (success) {
            (address royaltyRecipient, uint256 royaltyAmount) = IERC2981(address(nftContract)).royaltyInfo(tokenId, priceValue);
            IERC20(tokenAddress).transferFrom(msg.sender, royaltyRecipient, royaltyAmount);
            IERC20(tokenAddress).transferFrom(msg.sender, owner, priceValue - royaltyAmount);
            ERC721(collectionAddress).safeTransferFrom(owner, msg.sender, tokenId);
            emit ItemBought(msg.sender, collectionAddress, tokenId, priceValue);
        } else {
            IERC20(tokenAddress).transferFrom(msg.sender, owner, priceValue);
            ERC721(collectionAddress).safeTransferFrom(owner, msg.sender, tokenId);
            emit ItemBought(msg.sender, collectionAddress, tokenId, priceValue);
        }
    }

    // Function to buy NFT with native token (ethers).
    function buyItemWithNativeToken(address collectionAddress, uint256 tokenId, uint256 priceValue)
        public
        payable
        nonReentrant
    {
        ERC721 nftContract;
        nftContract = ERC721(collectionAddress);
        if(msg.value < priceValue) {
            revert PriceNotMet(collectionAddress, tokenId, priceValue);
        }
        address seller = nftContract.ownerOf(tokenId);
        bool success  = checkRoyalties(collectionAddress);
        if (success) {
            (address royaltyRecipient, uint256 royaltyAmount) = IERC2981(address(nftContract)).royaltyInfo(tokenId, priceValue);
            (bool successRoyalty, ) = payable(royaltyRecipient).call{value: royaltyAmount}("");
            require(successRoyalty, "Transfer failed");
            (bool successBuy, ) = payable(seller).call{value: msg.value - royaltyAmount}("");
            require(successBuy, "Transfer failed");
            ERC721(collectionAddress).safeTransferFrom(seller, msg.sender, tokenId);
            emit ItemBought(msg.sender, collectionAddress, tokenId, priceValue);
        } else {
            (bool successBuyWithoutRoyalty, ) = payable(seller).call{value: msg.value}("");
            require(successBuyWithoutRoyalty, "Transfer failed");
            ERC721(collectionAddress).safeTransferFrom(seller, msg.sender, tokenId);
            emit ItemBought(msg.sender, collectionAddress, tokenId, priceValue);
        }
    }

    // Returns the address that signed a given string message
    function verifyString(string memory message, uint8 v, bytes32 r, bytes32 s) public pure returns (address signer) {

        // The message header; we will fill in the length next
        string memory header = "\x19Ethereum Signed Message:\n000000";

        uint256 lengthOffset;
        uint256 length;
        assembly {
            // The first word of a string is its length
            length := mload(message)
            // The beginning of the base-10 message length in the prefix
            lengthOffset := add(header, 57)
        }

        // Maximum length we support
        require(length <= 999999);

        // The length of the message's length in base-10
        uint256 lengthLength = 0;

        // The divisor to get the next left-most message length digit
        uint256 divisor = 100000;

        // Move one digit of the message length to the right at a time
        while (divisor != 0) {

            // The place value at the divisor
            uint256 digit = length / divisor;
            if (digit == 0) {
                // Skip leading zeros
                if (lengthLength == 0) {
                    divisor /= 10;
                    continue;
                }
            }

            // Found a non-zero digit or non-leading zero digit
            lengthLength++;

            // Remove this digit from the message length's current value
            length -= digit * divisor;

            // Shift our base-10 divisor over
            divisor /= 10;

            // Convert the digit to its ASCII representation (man ascii)
            digit += 0x30;
            // Move to the next character and write the digit
            lengthOffset++;

            assembly {
                mstore8(lengthOffset, digit)
            }
        }

        // The null string requires exactly 1 zero (unskip 1 leading 0)
        if (lengthLength == 0) {
            lengthLength = 1 + 0x19 + 1;
        } else {
            lengthLength += 1 + 0x19;
        }

        // Truncate the tailing zeros from the header
        assembly {
            mstore(header, lengthLength)
        }

        // Perform the elliptic curve recover operation
        bytes32 check = keccak256(abi.encodePacked(header, message));

        return ecrecover(check, v, r, s);
    }

}
