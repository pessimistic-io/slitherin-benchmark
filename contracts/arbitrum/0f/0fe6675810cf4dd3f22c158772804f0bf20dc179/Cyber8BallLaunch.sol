// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {EIP712} from "./EIP712.sol";
import {ECDSA} from "./ECDSA.sol";
import {ERC721} from "./ERC721.sol";
import {ICyber8BallLaunch} from "./ICyber8BallLaunch.sol";
import {ERC721Queryable} from "./ERC721Queryable.sol";
import {ONFT721} from "./ONFT721.sol";

contract Cyber8BallLaunch is ONFT721, EIP712, ERC721Queryable, ICyber8BallLaunch {
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant TREASURY_RESERVE = 200;
    MintConfig public mintConfig;
    mapping(address => WalletMintCount) public walletMintCount;
    uint256 public nextTokenId;
    uint256 private _treasuryMintCount;
    string private _baseTokenURI;
    bytes32 private constant _PRIOR_MINT_TYPE_HASH =
        keccak256("PriorMint(address wallet,uint256 maxQuantity)");
    bytes32 private constant _WHITELIST_MINT_TYPE_HASH =
        keccak256("WhitelistMint(address wallet,uint256 maxQuantity)");

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 minGasToTransfer_,
        address lzEndpoint_
    )
        EIP712(name_, "1")
        ONFT721(name_, symbol_, minGasToTransfer_, lzEndpoint_)
        ERC721Queryable(MAX_SUPPLY)
    {}

    modifier checkMintQuantity(uint256 quantity) {
        if (quantity == 0) {
            revert InvalidMintQuantity();
        }
        if (nextTokenId + quantity > MAX_SUPPLY) {
            revert ExceedMaxSupply();
        }
        _;
    }

    function setBaseTokenURI(string calldata uri) external onlyOwner {
        _baseTokenURI = uri;
        emit TokenBaseURIUpdated(uri);
    }

    function setMintConfig(MintConfig calldata config) external onlyOwner {
        mintConfig = config;
        emit MintConfigUpdated(config);
    }

    function treasuryMint(uint256 quantity) external onlyOwner checkMintQuantity(quantity) {
        if (_treasuryMintCount + quantity > TREASURY_RESERVE) {
            revert ExceedMaxMintQuantity();
        }

        _treasuryMintCount += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(_msgSender(), nextTokenId++);
        }
    }

    function priorMint(
        uint256 quantity,
        uint256 maxQuantity,
        bytes calldata signature
    ) external nonReentrant checkMintQuantity(quantity) {
        address sender = _msgSender();

        if (!mintConfig.priorOpen) {
            revert MintNotOpen();
        }
        if (!_verifyPriorMint(maxQuantity, signature)) {
            revert SignatureInvalid();
        }
        if (walletMintCount[sender].priorMint + quantity > maxQuantity) {
            revert ExceedMaxMintQuantity();
        }

        walletMintCount[sender].priorMint += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(sender, nextTokenId++);
        }
    }

    function whitelistMint(
        uint256 quantity,
        uint256 maxQuantity,
        bytes calldata signature
    ) external nonReentrant checkMintQuantity(quantity) {
        address sender = _msgSender();

        if (!mintConfig.whitelistOpen) {
            revert MintNotOpen();
        }
        if (!_verifyWhitelistMint(maxQuantity, signature)) {
            revert SignatureInvalid();
        }
        if (walletMintCount[sender].whitelist + quantity > maxQuantity) {
            revert ExceedMaxMintQuantity();
        }

        walletMintCount[sender].whitelist += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(sender, nextTokenId++);
        }
    }

    function publicMint(uint256 quantity) external nonReentrant checkMintQuantity(quantity) {
        address sender = _msgSender();

        if (!mintConfig.publicOpen) {
            revert MintNotOpen();
        }
        if (
            walletMintCount[sender].publicMint + quantity >
            mintConfig.publicMaxMintQuantityPerWallet
        ) {
            revert ExceedMaxMintQuantity();
        }

        walletMintCount[sender].publicMint += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(sender, nextTokenId++);
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ONFT721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Queryable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _verifyWhitelistMint(
        uint256 maxQuantity,
        bytes calldata signature
    ) private view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_WHITELIST_MINT_TYPE_HASH, _msgSender(), maxQuantity))
        );
        return ECDSA.recover(digest, signature) == mintConfig.signer;
    }

    function _verifyPriorMint(
        uint256 maxQuantity,
        bytes calldata signature
    ) private view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_PRIOR_MINT_TYPE_HASH, _msgSender(), maxQuantity))
        );
        return ECDSA.recover(digest, signature) == mintConfig.signer;
    }

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint _tokenId
    ) internal virtual override {
        require(_tokenId < MAX_SUPPLY, "Cyber8Ball: invalid token id");
        super._creditTo(_srcChainId, _toAddress, _tokenId);
    }
}

