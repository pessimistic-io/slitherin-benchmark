// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Sinnesloschend.sol";
import "./ECDSA.sol";

CoSinnesloschen constant COSINNESLOSCHEN = CoSinnesloschen(
    0x243158d3c541A9eED8a359d172d6eF6B28bf6B51
);

contract CoSinnesloschenMinter is Ownable {
    using ECDSA for bytes32;

    mapping(address => bool) private claimed;
    bool public paused = true;
    address public mintSigner = 0x5B614c37AcAcf1Cf398224CE0B78884A06d0137B;

    function publicMint(uint256 amount, bytes memory signature) external {
        require(!paused, 'Mint inactive');
        bytes32 messageHash = getMessageHash(msg.sender, amount);
        require(verify(messageHash, signature), 'Invalid signature provided');
        require(!claimed[msg.sender], 'Minter already claimed');
        claimed[msg.sender] = true;
        COSINNESLOSCHEN.ownerMint(amount, msg.sender);
    }

    function getMessageHash(address to, uint amount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(to, amount));
    }

    function verify(bytes32 messageHash, bytes memory signature) public view returns (bool) {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        return ethSignedMessageHash.recover(signature) == mintSigner;
    }

    function setSigner(address newSigner) external onlyOwner {
        mintSigner = newSigner;
    }

    function ownerMint(uint256 amount, address recipient) external onlyOwner {
        COSINNESLOSCHEN.ownerMint(amount, recipient);
    }

    // Setters
    function setPaused(bool newState) external onlyOwner {
        paused = newState;
    }

    function transferOriginalOwnership(address newOwner) external onlyOwner {
        COSINNESLOSCHEN.transferOwnership(newOwner);
    }

    function setUriPrefix(string memory uri) external onlyOwner {
        COSINNESLOSCHEN.setUriPrefix(uri);
    }

    function setUriSuffix(string memory uri) external onlyOwner {
        COSINNESLOSCHEN.setUriSuffix(uri);
    }

    function setHiddenUri(string memory uri) external onlyOwner {
        COSINNESLOSCHEN.setHiddenUri(uri);
    }

    function setMaxMintPerWallet(uint256 number) external onlyOwner {
        COSINNESLOSCHEN.setMaxMintPerWallet(number);
    }

    function setMaxFreeMintPerWallet(uint256 number) external onlyOwner {
        COSINNESLOSCHEN.setMaxFreeMintPerWallet(number);
    }

    function setFreeMintRoot(bytes32 root) external onlyOwner {
        COSINNESLOSCHEN.setFreeMintRoot(root);
    }

    function setWlMintRoot(bytes32 root) external onlyOwner {
        COSINNESLOSCHEN.setWlMintRoot(root);
    }

    // Toggle
    function toggleEnablePublicMintCounter() external onlyOwner {
        COSINNESLOSCHEN.toggleEnablePublicMintCounter();
    }

    function toggleReveal() external onlyOwner {
        COSINNESLOSCHEN.toggleReveal();
    }

    // Withdraw
    function withdraw() external onlyOwner {
        COSINNESLOSCHEN.withdraw();
        if (address(this).balance > 0) {
            payable(owner()).transfer(address(this).balance);
        }
    }

    receive() external payable {}
}

