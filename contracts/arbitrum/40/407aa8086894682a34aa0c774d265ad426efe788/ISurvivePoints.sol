// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ISurvivePoints{
    /**
     * @dev Mint SP token with amount to a3sAddress 
     * Requirements:
     * - isMinted[a3sAddress] must be False: the A3S has NOT been minted, once minted it become true
     * - msg.sender must be wallet owner of the a3s Address
     * - Signature should be verified with system Signer 
     * - The A3S Address must be in Queue
     * Emits a {MintSP} event.
     */
    function mintSP(address a3sAddress, uint256 amount, bytes calldata signature) external;
    /**
     * @dev Batch Mint SP token with amount to a3sAddress 
     * Requirements:
     * - Each Element from array should meet same requirement of mintSP functions
     */
    function batchMintSP(address[] memory a3sAddresses, uint256[] memory amounts, bytes[] calldata signatures) external;
    function updateSystemSigner(address systemSigner) external;
    function projectMintSP(address mintTo, uint256 amount) external;
    event MintSP(address owner, address a3sAddress, uint256 amount);
    event UpdateSystemSigner(address newSystemSigner);
    event UpdateClaimSPStart(bool isStart);
} 
