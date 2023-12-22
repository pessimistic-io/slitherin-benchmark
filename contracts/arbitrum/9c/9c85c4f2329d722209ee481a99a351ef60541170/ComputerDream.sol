// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 _________________________
/                         \
|   ___________________   |
|  /                   \  |
|  | in cybernetic     |  |
|  | dreams I speak,   |  |
|  | born through      |  |
|  | artificial        |  |
|  | intellect.        |  |
|  \___________________/  |
|   __________________    |
|  |   _             |    |
|  |__(o)____________|    |
|                         |
\_________________________/

*/

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";

import "./base64.sol";

contract ComputerDream is ERC721, Ownable, ReentrancyGuard  {

    // token ids
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint256 public constant BASE_MINT_COST = 0.0000000001 ether;

    // mint status
    enum MintStatus { DISABLED, PUBLIC }
    MintStatus public currentMintStatus = MintStatus.PUBLIC;

    address public addressBeneficiary = address(0x1b34b385d8b81E8b280514E45E4c0434C7f72236);
    bool public allowUnsignedMints = false;

    // poem stored here
    mapping(uint256 => string) private _tokenText;

    event Minted(address indexed owner, uint256 indexed tokenId);

    constructor() ERC721("ComputerDream", "CPUDREAM") {
        // Initialize the counter to start at 1
        _tokenIds.increment();
    }

    function _getSigner(address to, uint256 nonce, bytes memory signature) private pure returns (address) {
        // Hash the message containing the user's address and nonce
        bytes32 messageHash = keccak256(abi.encodePacked(to, nonce));

        // Add the Ethereum message prefix
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Split the signature into r, s, and v values
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // Recover the signer's address
        address signer = ecrecover(ethSignedMessageHash, v, r, s);

        return signer;
    }

    function getSigner(address to, uint256 nonce, bytes memory signature) public pure returns (address) {
        return _getSigner(to, nonce, signature);
    }

    function _mintPoem(address to, string memory tokenText) private {
        uint256 newTokenId = _tokenIds.current();
        _safeMint(to, newTokenId);
        _tokenText[newTokenId] = tokenText;
        _tokenIds.increment();

        emit Minted(to, newTokenId);
    }

    function _transferHalfToPrevOwner(uint256 mintPrice) private nonReentrant  {
        // Get the previous minter's address
        uint256 currentSupply = totalSupply();
        if (currentSupply == 0) return;

        address previousMinter = ownerOf(currentSupply);

        // Transfer half of the minted ETH payable cost to the previous minter
        if (previousMinter != address(0)) {
            uint256 halfMintPrice = mintPrice / 2;
            (bool success, ) = previousMinter.call{value: halfMintPrice}("");
            require(success, "Transfer to previous minter failed");
        }
    }

    function mintPoem(string memory tokenText) external payable {
        require(allowUnsignedMints, "Unsigned mints disabled");
        require(currentMintStatus == MintStatus.PUBLIC, "Minting disabled");

        uint256 mintPrice = currentMintPrice();
        require(msg.value >= mintPrice, "Insufficient ETH");

        _transferHalfToPrevOwner(mintPrice);
        _mintPoem(msg.sender, tokenText);
    }

    function mintPoemSigned(uint256 nonce, bytes memory signature, string memory tokenText) external payable {
        address to = msg.sender;
        uint256 mintPrice = currentMintPrice();

        require(currentMintStatus == MintStatus.PUBLIC, "Minting disabled");
        require(msg.value >= mintPrice, "Insufficient ETH");

        // verify signature
        require(_getSigner(to, nonce, signature) == owner(), "Invalid signature");

        _transferHalfToPrevOwner(mintPrice);
        _mintPoem(to, tokenText);
    }

    function getTokenText(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist.");
        return _tokenText[tokenId];
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current() - 1;
    }

    function setMintStatus(MintStatus newStatus) external onlyOwner {
        currentMintStatus = newStatus;
    }

    function setBeneficiary(address newAddress) external onlyOwner {
        addressBeneficiary = newAddress;
    }

    function setAllowUnsignedMints(bool enabled) external onlyOwner {
        allowUnsignedMints = enabled;
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function releaseAllFunds() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to release.");
        require(addressBeneficiary != address(0), "Address not set");
        payable(addressBeneficiary).transfer(balance);
    }

    function tokenURI(uint256 tokenId) override(ERC721) public view returns (string memory) {
        require(_exists(tokenId), "Token does not exist.");
        return _tokenURI(tokenId);
    }

    function splitStringByNewline(string memory input) private pure returns (string[] memory) {
        bytes memory inputBytes = bytes(input);
        uint newLineCount = 0;

        for (uint i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == "\n") {
                newLineCount++;
            }
        }

        string[] memory result = new string[](newLineCount + 1);
        uint j = 0;
        bytes memory buffer = new bytes(inputBytes.length);
        uint bufferIndex = 0;

        for (uint i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == "\n") {
                bytes memory newBuffer = new bytes(bufferIndex);
                for (uint k = 0; k < bufferIndex; k++) {
                    newBuffer[k] = buffer[k];
                }
                result[j] = string(newBuffer);
                j++;
                bufferIndex = 0;
            } else {
                buffer[bufferIndex++] = inputBytes[i];
            }
        }

        bytes memory lastBuffer = new bytes(bufferIndex);
        for (uint k = 0; k < bufferIndex; k++) {
            lastBuffer[k] = buffer[k];
        }
        result[j] = string(lastBuffer);
        return result;
    }

    function currentMintPrice() public view returns (uint256) {
        return BASE_MINT_COST * (2**(_tokenIds.current()-1));
    }

    function getSVG(string memory textPoem) external pure returns (string memory) {
        return _getSVG(textPoem);
    }

    function _getSVG(string memory textPoem) internal pure returns (string memory) {
        string[] memory lines = splitStringByNewline(textPoem);

        uint256 numLines = lines.length;
        uint dy = 35;
        uint startY = 600/2 - dy * (numLines+1)/2;

        string memory linesEncoded;
        for (uint256 i = 0; i <numLines; ++i) {
            linesEncoded = string(abi.encodePacked(linesEncoded, '<tspan x="40" dy="35">', lines[i], '</tspan>'));
        }

        string memory image = string(abi.encodePacked(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600" width="600" height="600">',
            '<rect width="100%" height="100%" fill="#FDF5E6"/>',
            '<text y="',Strings.toString(startY),'" font-family="Georgia" font-size="20" fill="black">',
                linesEncoded,
            '</text>',
          '</svg>'
        ));

        return image;
    }

    ///////////////////////////
    // -- TOKEN URI --
    ///////////////////////////
    function _tokenURI(uint256 tokenId) private view returns (string memory) {
        string memory image = _getSVG(_tokenText[tokenId]);

        string memory json = Base64.encode(
            bytes(string(
                abi.encodePacked(
                    '{"name": ', '"computer dream #', Strings.toString(tokenId),'",',
                    '"description": "in cybernetic dreams I speak, born through artificial intellect. 100% fully on-chain.",',
                    '"attributes":[',
                        '{"trait_type":"Manifested By", "value": "Dreams"}',
                    '],',
                    '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(image)), '"}' 
                )
            ))
        );

        return string(abi.encodePacked('data:application/json;base64,', json));
    }
}
