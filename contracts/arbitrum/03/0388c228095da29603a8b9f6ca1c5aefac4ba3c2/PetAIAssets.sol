// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./IERC20.sol";

import "./IERC721Launchpad.sol";
import "./TimeSkippable.sol";
import "./Withdraw.sol";
import "./SignTypedData.sol";

contract PetAIAssets is
    IERC721Launchpad,
    ERC721Enumerable,
    Ownable,
    SignTypedData,
    Withdraw
{
    using Counters for Counters.Counter;

    address private signerAllowed;
    string private baseTokenURI;
    Counters.Counter private tokenIdCount;

    mapping(address => mapping(uint256 => uint256)) walletSessionMinted;
    mapping(uint256 => uint256) sessionMinted;
    mapping(uint256 => string) tokenIdentify;
    mapping(string => bool) existedTokenIdentify;

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        address signerAllowed_,
        string memory baseTokenURI_,
        string memory domainName,
        string memory domainVersion
    ) ERC721(name, symbol) SignTypedData(domainName, domainVersion) {
        transferOwnership(owner);
        signerAllowed = signerAllowed_;
        baseTokenURI = baseTokenURI_;
    }

    function setSignerAllowed(address signerAllowed_) public {
        signerAllowed = signerAllowed_;
    }

    function getSignerAllowed() public view returns (address) {
        return signerAllowed;
    }

    function stopSignMint() public {
        signerAllowed = address(0);
    }

    modifier validateSignMint(
        SignMintParams memory params,
        bytes memory signature
    ) {
        require(signerAllowed != address(0), "SIGN_MINT_STOPPED");

        bytes32 _dataHash = keccak256(
            abi.encode(
                params.mintSessionId,
                params.mintSessionLimit,
                params.walletMintSessionLimit,
                params.fee,
                params.feeErc20Address,
                params.tokenIdentify
            )
        );
        address signer = _recoverSigner(_dataHash, signature);
        require(signer == signerAllowed, "INVALID_SIGNATURE");

        if (params.walletMintSessionLimit > 0)
            require(
                getWalletSessionMinted(_msgSender(), params.mintSessionId) <
                    params.walletMintSessionLimit,
                "EXCEED_WALLET_LIMIT"
            );

        if (params.mintSessionLimit > 0)
            require(
                getSessionMinted(params.mintSessionId) <
                    params.mintSessionLimit,
                "EXCEED_SESSION_LIMIT"
            );

        if (bytes(params.tokenIdentify).length > 0)
            require(
                existedTokenIdentify[params.tokenIdentify] == false,
                "TOKEN_IDENTIFY_EXISTED"
            );
        _;
    }

    function getWalletSessionMinted(
        address wallet,
        uint256 mintSessionId
    ) public view returns (uint256) {
        return walletSessionMinted[wallet][mintSessionId];
    }

    function getTokenIdentify(
        uint256 tokenId
    ) public view returns (string memory) {
        return tokenIdentify[tokenId];
    }

    function getSessionMinted(
        uint256 mintSessionId
    ) public view returns (uint256) {
        return sessionMinted[mintSessionId];
    }

    function signMint(
        SignMintParams memory params,
        bytes memory signature
    ) public payable validateSignMint(params, signature) returns (uint256) {
        if (params.fee > 0) {
            // Pay fee with eth
            if (params.feeErc20Address == IERC20(address(0))) {
                payable(_msgSender()).transfer((params.fee));
            }

            // Pay fee with ERC20
            if (params.feeErc20Address != IERC20(address(0))) {
                params.feeErc20Address.transferFrom(
                    _msgSender(),
                    address(this),
                    params.fee
                );
            }
        }

        // Start Mint
        tokenIdCount.increment();
        uint256 _tokenId = tokenIdCount.current();
        _mint(_msgSender(), _tokenId);
        // Stop Mint

        walletSessionMinted[_msgSender()][params.mintSessionId] += 1;
        sessionMinted[params.mintSessionId] += 1;

        if (bytes(params.tokenIdentify).length > 0) {
            tokenIdentify[_tokenId] = params.tokenIdentify;
            existedTokenIdentify[params.tokenIdentify] = true;
        }

        return _tokenId;
    }

    function safeMint(
        string memory tokenIdentify_,
        address to
    ) public onlyOwner returns (uint256) {
        // Start Mint
        tokenIdCount.increment();
        uint256 _tokenId = tokenIdCount.current();
        _mint(to, _tokenId);
        // Stop Mint

        tokenIdentify[_tokenId] = tokenIdentify_;

        return _tokenId;
    }

    function mint(address to) public onlyOwner returns (uint256) {
        // Start Mint
        tokenIdCount.increment();
        uint256 _tokenId = tokenIdCount.current();
        _mint(to, _tokenId);
        // Stop Mint

        return _tokenId;
    }

    function baseURI() public view returns (string memory) {
        return baseTokenURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI();
    }

    function setBaseURI(string memory baseTokenURI_) public onlyOwner {
        baseTokenURI = baseTokenURI_;
    }
}

