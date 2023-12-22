// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICyber8BallLaunch {
    struct WalletMintCount {
        uint256 priorMint;
        uint256 whitelist;
        uint256 publicMint;
    }

    struct MintConfig {
        bool priorOpen;
        bool whitelistOpen;
        bool publicOpen;
        address signer;
        uint256 publicMaxMintQuantityPerWallet;
    }

    error MintNotOpen();
    error SignatureInvalid();
    error ExceedMaxSupply();
    error ExceedMaxMintQuantity();
    error InvalidMintQuantity();

    event TokenBaseURIUpdated(string uri);
    event MintConfigUpdated(MintConfig config);
}

