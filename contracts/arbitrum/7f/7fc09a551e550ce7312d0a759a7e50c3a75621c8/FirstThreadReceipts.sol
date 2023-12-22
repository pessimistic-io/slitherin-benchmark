/// SPDX-License-Identifier: UNLICENSED
//Test
pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./Owned.sol";
import "./ReentrancyGuard.sol";
import "./Base64.sol";
import "./LibString.sol";
import "./ECDSA.sol";
import "./ITHREETHREETHREE.sol";
import "./IERC20.sol";
import "./ERC721_IERC721.sol";

/// @title First Thread Receipt Issuer
/// @author BlockLineChef & ET
/// @notice Compatible with GobDrops ERC721 & ERC1155 contracts that implement permissioned burn functions

contract FirstThreadReceipts is ERC721, Owned, ReentrancyGuard {
    using LibString for uint256;
    using ECDSA for bytes32;

    enum ShippingPaymentType {
        Ether,
        ERC20
    }

    enum ReceiptType {
        GobDropEther,
        GobDropERC20,
        BurnImplementerEther,
        BurnImplementerERC20,
        BurnImplementerGobDropEther,
        BurnImplementerGobDropERC20
    }

    struct GobDropEtherReceipt  {
        uint[] gobDropTokenIds;
        uint etherPaymentAmount;
    }

    struct GobDropERC20Receipt {
        uint[] gobDropTokenIds;
        uint erc20PaymentAmount;
        address erc20Contract;
    }

    struct BurnImplementerEtherReceipt {
        address[] burnImplementerContracts;
        bytes32[] tokenIds;
        bytes32[] tokenAmounts;        
        uint etherPaymentAmount;
    }

    struct BurnImplementerERC20Receipt {
        address[] burnImplementerContracts;        
        bytes32[] tokenIds;
        bytes32[] tokenAmounts;
        uint erc20PaymentAmount;
        address erc20Contract;
    }

    struct BurnImplementerGobDropEtherReceipt {
        address[] burnImplementerContracts;        
        bytes32[] tokenIds;
        bytes32[] tokenAmounts;
        uint[] gobDropTokenIds;
        uint etherPaymentAmount;
    }

    struct BurnImplementerGobDropERC20Receipt {
        address[] burnImplementerContracts;        
        bytes32[] tokenIds;
        bytes32[] tokenAmounts;
        uint[] gobDropTokenIds;
        uint erc20PaymentAmount;
        address erc20Contract;
    }

    mapping(uint => GobDropEtherReceipt) public gobDropEtherReceipts;
    mapping(uint => GobDropERC20Receipt) public gobDropERC20Receipts;
    mapping(uint => BurnImplementerEtherReceipt) public burnImplementerEtherReceipts;
    mapping(uint => BurnImplementerERC20Receipt) public burnImplementerERC20Receipts;
    mapping(uint => BurnImplementerGobDropEtherReceipt) public burnImplementerGobDropEtherReceipts;
    mapping(uint => BurnImplementerGobDropERC20Receipt) public burnImplementerGobDropERC20Receipts;

    mapping(uint => ReceiptType) public receiptTypes;

    address public gobDropsContractAddress;
    address constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    address public signerAddress;

    uint public tokenCounter; 
    string public baseURI;

    constructor(address _signer, address _owner, address _gobDropsContractAddress) ERC721("FirstThreadReceipts", "FTR") Owned(_owner) {
        signerAddress = _signer;
        gobDropsContractAddress = _gobDropsContractAddress;
    }

    /// @notice Generate Receipt from Gob Drops, pay fee in ETH
    /// @dev Must approve this contract to spend GobDrops first
    /// @param tokenIds Array of GobDrop token IDs
    /// @param expiry Expiry for signature
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptGobDropEther(
        uint[] calldata tokenIds,
        uint expiry,
        bytes32 messageHash,
        bytes calldata signature
    ) external payable nonReentrant {
        require(block.timestamp < expiry, "Signature Expired");
        require(hashGenerateReceiptGobDropEther(tokenIds, msg.value, address(this), msg.sender, expiry) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        burnGobDrops(tokenIds);
        GobDropEtherReceipt memory gobDropEtherReceipt = GobDropEtherReceipt(tokenIds, msg.value);
        gobDropEtherReceipts[tokenCounter] = gobDropEtherReceipt;
        receiptTypes[tokenCounter] = ReceiptType.GobDropEther;
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }
    
    /// @notice Generate Receipt from Gob Drops, pay fee in ERC20 determined by the First Thread backend
    /// @dev Must approve this contract to spend GobDrops first
    /// @dev Must approve this contract to spend paymentToken first
    /// @param tokenIds Array of GobDrop token IDs
    /// @param paymentAmount Payment amount of the ERC20 token
    /// @param paymentToken Address of payment token
    /// @param expiry Expiry for signature 
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptGobDropERC20(
        uint[] calldata tokenIds,
        uint paymentAmount,
        address paymentToken,
        uint expiry,
        bytes32 messageHash,
        bytes calldata signature
    ) external nonReentrant {
        require(block.timestamp < expiry, "Signature Expired");
        require(hashGenerateReceiptGobDropERC20(tokenIds, paymentAmount, paymentToken, address(this), msg.sender, expiry) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        burnGobDrops(tokenIds);
        GobDropERC20Receipt memory gobDropERC20Receipt = GobDropERC20Receipt(tokenIds, paymentAmount, paymentToken);
        gobDropERC20Receipts[tokenCounter] = gobDropERC20Receipt;
        receiptTypes[tokenCounter] = ReceiptType.GobDropERC20;
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }

    /// @notice Generate Receipt from burn implementer ERC1155 collections, pay fee in ETH
    /// @dev No approval needed
    /// @dev Each contractAddress represents each subsequent 2 tokenIds & 2 amounts.
    /// @dev Each tokenId & amount each contain up to 10 values in the bytestrings, allowing for up to 20 values per contract address
    /// @param contractAddresses Array of ERC1155 contract addresses
    /// @param tokenIds Array of GobDrop token IDs
    /// @param amounts Amounts for each tokenId
    /// @param expiry Expiry for signature
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptBurnImplementerEther(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts,
        uint expiry,
        bytes32 messageHash,
        bytes calldata signature
    ) external payable nonReentrant {
        require(block.timestamp < expiry, "Signature Expired");
        require(hashGenerateReceiptBurnImplementerEther(contractAddresses, tokenIds, amounts, msg.value, address(this), msg.sender, expiry) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        burnImplementerBatch(contractAddresses, tokenIds, amounts);
        BurnImplementerEtherReceipt memory burnImplementerEtherReceipt = BurnImplementerEtherReceipt(contractAddresses, tokenIds, amounts, msg.value);
        burnImplementerEtherReceipts[tokenCounter] = burnImplementerEtherReceipt;
        receiptTypes[tokenCounter] = ReceiptType.BurnImplementerEther;
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }
    
    /// @notice Generate Receipt from burn implementer ERC1155 collections, pay fee in ERC20
    /// @dev Must approve this contract to spend paymentToken first
    /// @dev Each contractAddress represents each subsequent 2 tokenIds & 2 amounts.
    /// @dev Each tokenId & amount each contain up to 10 values in the bytestrings, allowing for up to 20 values per contract address
    /// @param contractAddresses Array of ERC1155 contract addresses
    /// @param tokenIds Array of GobDrop token IDs
    /// @param amounts Amounts for each tokenId
    /// @param paymentAmount Payment amount of the ERC20 token
    /// @param paymentToken Address of payment token
    /// @param expiry Expiry for signature
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptBurnImplementerERC20(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts,
        uint paymentAmount,
        address paymentToken,
        uint expiry,
        bytes32 messageHash,
        bytes calldata signature
    ) external nonReentrant {
        require(block.timestamp < expiry, "Signature Expired");
        require(hashGenerateReceiptBurnImplementerERC20(contractAddresses, tokenIds, amounts, paymentAmount, paymentToken, address(this), msg.sender, expiry) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        burnImplementerBatch(contractAddresses, tokenIds, amounts);
        BurnImplementerERC20Receipt memory burnImplementerERC20Receipt = BurnImplementerERC20Receipt(contractAddresses, tokenIds, amounts, paymentAmount, paymentToken);
        burnImplementerERC20Receipts[tokenCounter] = burnImplementerERC20Receipt;
        receiptTypes[tokenCounter] = ReceiptType.BurnImplementerERC20;        
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }

    /// @notice Generate Receipt from burn implementer ERC1155 collections & GobDrops, pay fee in ETH
    /// @dev Must approve this contract to spend GobDrops first
    /// @dev Each contractAddress represents each subsequent 2 tokenIds & 2 amounts.
    /// @dev Each tokenId & amount each contain up to 10 values in the bytestrings, allowing for up to 20 values per contract address
    /// @param contractAddresses Array of ERC1155 contract addresses
    /// @param tokenIds Array of GobDrop token IDs
    /// @param amounts Amounts for each tokenId
    /// @param gobDropTokenIds Array of GobDrop token IDs
    /// @param expiry Expiry for signature
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptBurnImplementerGobDropEther(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts,
        uint[] calldata gobDropTokenIds,
        uint expiry,
        bytes32 messageHash,
        bytes calldata signature
    ) external payable nonReentrant {
        require(block.timestamp < expiry, "Signature Expired");
        require(hashGenerateReceiptBurnImplementerGobDropEther(contractAddresses, tokenIds, amounts, gobDropTokenIds, msg.value, address(this), msg.sender, expiry) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        burnImplementerBatch(contractAddresses, tokenIds, amounts);        
        burnGobDrops(gobDropTokenIds);
        BurnImplementerGobDropEtherReceipt memory burnImplementerGobDropEtherReceipt = BurnImplementerGobDropEtherReceipt(contractAddresses, tokenIds, amounts, gobDropTokenIds, msg.value);
        burnImplementerGobDropEtherReceipts[tokenCounter] = burnImplementerGobDropEtherReceipt;
        receiptTypes[tokenCounter] = ReceiptType.BurnImplementerGobDropEther;
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }
    
    /// @notice Generate Receipt from burn implementer ERC1155 collections & GobDrops, pay fee in ERC20
    /// @dev Must approve this contract to spend GobDrops first
    /// @dev Must approve this contract to spend paymentToken first
    /// @dev Each contractAddress represents each subsequent 2 tokenIds & 2 amounts.
    /// @dev Each tokenId & amount each contain up to 10 values in the bytestrings, allowing for up to 20 values per contract address
    /// @param contractAddresses Array of ERC1155 contract addresses
    /// @param tokenIds Array of GobDrop token IDs
    /// @param amounts Amounts for each tokenId
    /// @param gobDropTokenIds Array of GobDrop token IDs
    /// @param paymentAmountAndExpiry ERC20 payment amount and signature expiry
    /// @param paymentToken ERC20 payment token address
    /// @param messageHash Message hash
    /// @param signature Signature
    function generateReceiptBurnImplementerGobDropERC20(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts,
        uint[] memory gobDropTokenIds,
        uint[] memory paymentAmountAndExpiry,
        address paymentToken,
        bytes32 messageHash,
        bytes calldata signature
    ) external nonReentrant {
        require(block.timestamp < paymentAmountAndExpiry[1], "Signature Expired");
        require(hashGenerateReceiptBurnImplementerGobDropERC20(contractAddresses, tokenIds, amounts, gobDropTokenIds, paymentAmountAndExpiry, paymentToken, address(this), msg.sender) == messageHash, "Invalid message hash.");
        require(verifyAddressSigner(messageHash, signature), "Invalid signature.");
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmountAndExpiry[0]);
        burnImplementerBatch(contractAddresses, tokenIds, amounts);        
        burnGobDrops(gobDropTokenIds);
        BurnImplementerGobDropERC20Receipt memory burnImplementerGobDropERC20Receipt = BurnImplementerGobDropERC20Receipt(contractAddresses, tokenIds, amounts, gobDropTokenIds, paymentAmountAndExpiry[0], paymentToken);
        burnImplementerGobDropERC20Receipts[tokenCounter] = burnImplementerGobDropERC20Receipt;
        receiptTypes[tokenCounter] = ReceiptType.BurnImplementerGobDropERC20;
        _mint(msg.sender, tokenCounter);
        unchecked {
            tokenCounter++;
        }
    }

    function hashGenerateReceiptGobDropEther(
        uint[] calldata tokenIds,
        uint etherSent,
        address contractAddress,
        address sender,
        uint expiry
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds, etherSent, contractAddress, sender, expiry));
    }

    function hashGenerateReceiptGobDropERC20(
        uint[] calldata tokenIds,
        uint paymentAmount,
        address paymentToken,
        address contractAddress,
        address sender,
        uint expiry
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds, paymentAmount, paymentToken, contractAddress, sender, expiry));
    }

    function hashGenerateReceiptBurnImplementerEther(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts,
        uint etherSent,
        address contractAddress,
        address sender,
        uint expiry
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddresses, tokenIds, amounts, etherSent, contractAddress, sender, expiry));
    }

    function hashGenerateReceiptBurnImplementerERC20(
        address[] memory contractAddresses,
        bytes32[] memory tokenIds,
        bytes32[] memory amounts,
        uint paymentAmount,
        address paymentToken,
        address contractAddress,
        address sender,
        uint expiry
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddresses, tokenIds, amounts, paymentAmount, paymentToken, contractAddress, sender, expiry));
    }

    function hashGenerateReceiptBurnImplementerGobDropEther(
        address[] memory contractAddresses,
        bytes32[] memory tokenIds,
        bytes32[] memory amounts,
        uint[] memory gobDropTokenIds,
        uint etherSent,
        address contractAddress,
        address sender,
        uint expiry
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddresses, tokenIds, amounts, gobDropTokenIds, etherSent, contractAddress, sender, expiry));
    }

    function hashGenerateReceiptBurnImplementerGobDropERC20(
        address[] memory contractAddresses,
        bytes32[] memory tokenIds,
        bytes32[] memory amounts,
        uint[] memory gobDropTokenIds,
        uint[] memory paymentAmountAndExpiry,
        address paymentToken,
        address contractAddress,
        address sender
        ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractAddresses, tokenIds, amounts, gobDropTokenIds, paymentAmountAndExpiry[0], paymentToken, contractAddress, sender, paymentAmountAndExpiry[1]));
    }

    // @notice This function is used to burn multiple tokens from multiple contracts at once.
    // @param contractAddresses - An array of contract addresses to burn from, they must implement admin burn functions.
    // @param tokenIds - An array of byte strings that contain the token ids to burn.
    // @param amounts - An array of byte strings that contain the amounts to burn.
    function burnImplementerBatch(
        address[] calldata contractAddresses,
        bytes32[] calldata tokenIds,
        bytes32[] calldata amounts
    ) internal {
        for(uint i = 0; i < contractAddresses.length; i++) {
            bytes32 tokenIds1 = tokenIds[0 + i*2];
            bytes32 tokenIds2 = tokenIds[1 + i*2];
            bytes32 amounts1 = amounts[0 + i*2];
            bytes32 amounts2 = amounts[1 + i*2];

            uint[] memory finalTokenIds = new uint256[](10);
            uint[] memory finalAmounts = new uint256[](10);

            for(uint j = 0; j < 20; j++) {
                uint tokenId;
                uint amount;

                if(j < 10){
                    assembly {
                        tokenId := and(shr(mul(j, 0x18), tokenIds1), 0xfffff)
                        amount := and(shr(mul(j, 0x18), amounts1), 0xfffff)
                    }
                } else {
                    assembly {
                        tokenId := and(shr(mul(j, 0x18), tokenIds2), 0xfffff)
                        amount := and(shr(mul(j, 0x18), amounts2), 0xfffff)
                    }                    
                }
                
                if (tokenId == 0 && j != 0) { break; }
                if (amount == 0 && j != 0) { break; }

                finalTokenIds[j] = tokenId;
                finalAmounts[j] = amount;

            }
            ITHREETHREETHREE(contractAddresses[i]).burnBatch(msg.sender, finalTokenIds, finalAmounts);
        }
    }

    // @notice This function is used to transfer multiple tokens from the GobDrops contract to the burn address.
    // @param tokenIds - An array of token ids to burn.
    function burnGobDrops(
        uint[] memory tokenIds
    ) internal {
        for(uint i = 0; i < tokenIds.length; i++) {
            IERC721(gobDropsContractAddress).transferFrom(msg.sender, deadAddress, tokenIds[i]);
        }
    }

    /// @notice Verifies the signature signer matches the signature address.
    /// @param messageHash The hash of the function parameters needing to be enforces via offchain signature.
    /// @param signature The signature of the messageHash.
    /// @return bool True if the signature is valid.
    function verifyAddressSigner(
        bytes32 messageHash,
        bytes calldata signature
    ) private view returns (bool) {
        address recovery = messageHash.toEthSignedMessageHash().recover(signature);
        return signerAddress == recovery;
    }

    function tokenURI(uint tokenID) public view override returns (string memory) {
        require(tokenID < tokenCounter, "This token does not exist");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenID.toString())) : "";
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function changeBaseURI(string calldata newBaseURI) external onlyOwner {
      baseURI = newBaseURI;
    }

    function setgobDropsContractAddress(address _gobDropsContractAddress) external onlyOwner {
        gobDropsContractAddress = _gobDropsContractAddress;
    }

    function setSigner(address _signer) external onlyOwner {
        signerAddress = _signer;
    }

    function withdrawEther() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawERC20(address _erc20Contract) external onlyOwner {
        IERC20 erc20Contract = IERC20(_erc20Contract);
        erc20Contract.transfer(msg.sender, erc20Contract.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                        SOULBOUND OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function transferFrom(address from, address to, uint id) override public pure {
        revert("This contract does not support transfers");
    }

    function safeTransferFrom(address from, address to, uint id) override public pure {
        revert("This contract does not support transfers");
    } 
}
