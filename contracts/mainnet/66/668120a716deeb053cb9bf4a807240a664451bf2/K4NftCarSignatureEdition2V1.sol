// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ECDSA.sol";
import "./ERC721.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract K4NftCarSignatureEdition2V1 is ERC721, Ownable, ReentrancyGuard {
    uint256 private constant NFTTOTALSUPPLY = 999;
    bool public isSaleActive = true;
    uint256 private constant _CONTRACTID = 12;

    event NFTMinted(
        address _to,
        uint256 indexed _tokenId,
        uint256 indexed _quantity,
        bool _success,
        uint256 _contractID
    );
    event TokenTransfered(
        address _token,
        address _from,
        address _to,
        uint256 indexed _amount
    );

    mapping(bytes => bool) private signatureUsed;
    mapping(address => bool) private whitelistedAddress;

    constructor()
        ERC721(
            "K4 Rally NFT Car - Signature Edition #2 - Jan Cerny",
            "K4CARSE"
        )
    {}

    function contractURI() public pure returns (string memory) {
        return "https://game.k4rally.io/nft/car/12/";
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://game.k4rally.io/nft/car/12/";
    }

    modifier isWhitelisted(address _address) {
        require(whitelistedAddress[_address], "You need to be whitelisted");
        _;
    }

    function safeMintUsingEther(
        uint256[] memory tokenId,
        uint256 quantity,
        bytes32 hash,
        bytes memory signature
    ) public payable nonReentrant {
        require(quantity <= 10, "Cannot buy more than 10 nfts");
        require(quantity != 0, "Insufficient quantity");
        require(isSaleActive, "Sale Inactive");
        require(msg.value != 0, "Insufficient amount");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        require(tokenId.length == quantity, "Invalid parameter");
        for (uint256 i = 0; i < quantity; i++) {
            if (tokenId[i] <= NFTTOTALSUPPLY && !_exists(tokenId[i])) {
                _safeMint(msg.sender, tokenId[i]);
                emit NFTMinted(
                    msg.sender,
                    tokenId[i],
                    quantity,
                    true,
                    _CONTRACTID
                );
            } else {
                emit NFTMinted(
                    msg.sender,
                    tokenId[i],
                    quantity,
                    false,
                    _CONTRACTID
                );
            }
        }
        signatureUsed[signature] = true;
    }

    function safeMintUsingToken(
        uint256[] memory tokenId,
        address tokenAddress,
        uint256 amount,
        uint256 quantity,
        bytes32 hash,
        bytes memory signature
    ) public {
        require(quantity <= 10, "Cannot buy more than 10 nfts");
        require(quantity != 0, "Insufficient quantity");
        require(isSaleActive, "Sale Inactive");
        require(amount != 0, "Insufficient amount");
        require(tokenAddress != address(0), "Address cannot be zero");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        require(tokenId.length == quantity, "Invalid parameter");
        IERC20 token;
        token = IERC20(tokenAddress);
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "Check the token allowance"
        );
        for (uint256 i = 0; i < quantity; i++) {
            if (tokenId[i] <= NFTTOTALSUPPLY && !_exists(tokenId[i])) {
                _safeMint(msg.sender, tokenId[i]);
                emit NFTMinted(
                    msg.sender,
                    tokenId[i],
                    quantity,
                    true,
                    _CONTRACTID
                );
            } else {
                emit NFTMinted(
                    msg.sender,
                    tokenId[i],
                    quantity,
                    false,
                    _CONTRACTID
                );
            }
        }
        signatureUsed[signature] = true;
        emit TokenTransfered(tokenAddress, msg.sender, address(this), amount);
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    function mintHotWallet(
        uint256[] memory tokenId,
        uint256 quantity,
        address to
    ) external isWhitelisted(msg.sender){
        require(quantity <= 10, "Cannot buy more than 10 nfts");
        require(quantity != 0, "Insufficient quantity");
        require(isSaleActive, "Sale Inactive");
        require(
            to != address(0),
            "Address cannot be zero"
        );
        require(tokenId.length == quantity, "Invalid parameter");
        for (uint256 i = 0; i < quantity; i++) {
            if (tokenId[i] <= NFTTOTALSUPPLY && !_exists(tokenId[i])) {
                _safeMint(to, tokenId[i]);
                emit NFTMinted(to, tokenId[i], quantity, true, _CONTRACTID);
            } else {
                emit NFTMinted(
                    to,
                    tokenId[i],
                    quantity,
                    false,
                    _CONTRACTID
                );
            }
        }
    }

    function directMint(
        uint256 tokenId,
        bytes32 hash,
        bytes memory signature
    ) external {
        require(isSaleActive, "Sale Inactive");
        require(
            recoverSigner(hash, signature) == owner(),
            "Address is not authorized"
        );
        require(!signatureUsed[signature], "Already signature used");
        if (tokenId <= NFTTOTALSUPPLY && !_exists(tokenId)) {
            _safeMint(msg.sender, tokenId);
            emit NFTMinted(msg.sender, tokenId, 1,true, _CONTRACTID);
        } else {
            emit NFTMinted(
                msg.sender,
                tokenId,
                0,
                false,
                _CONTRACTID
            );
        }
        signatureUsed[signature] = true;
    }

    function withdraw(address payable recipient) public onlyOwner {
        require(recipient != address(0), "Address cannot be zero");
        recipient.transfer(address(this).balance);
    }

    function withdrawToken(address tokenAddress, address recipient)
        public
        onlyOwner
    {
        require(recipient != address(0), "Address cannot be zero");
        IERC20 token;
        token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) > 0, "Insufficient balance");
        SafeERC20.safeTransfer(
            token,
            recipient,
            token.balanceOf(address(this))
        );
    }

    function setHotwalletAddress(address user) external onlyOwner {
        require(user != address(0), "Address cannot be 0");
        require(!whitelistedAddress[user], "User already exists");
        whitelistedAddress[user] = true;
    }

    function removeHotwalletAddress(address user) public onlyOwner {
        require(user != address(0), "Address cannot be 0");
        whitelistedAddress[user] = false;
    }

    function getWhiteListedAddress(address _address)
        external
        view
        onlyOwner
        returns (bool)
    {
        return whitelistedAddress[_address];
    }

    function flipSaleStatus() public onlyOwner {
        isSaleActive = !isSaleActive;
    }

    function recoverSigner(bytes32 hash, bytes memory signature)
        internal
        pure
        returns (address)
    {
        bytes32 messageDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        return ECDSA.recover(messageDigest, signature);
    }
}
