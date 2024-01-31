/**
SPDX-License-Identifier: MIT
*/

pragma solidity ^0.8.13;

import "./ERC721A.sol";
import "./ERC2981.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./draft-EIP712.sol";
import "./DefaultOperatorFilterer.sol";

contract AmartyaGate is
    ERC721A,
    DefaultOperatorFilterer,
    ERC2981,
    EIP712,
    ReentrancyGuard,
    Ownable
{
    using ECDSA for bytes32;

    enum Stage {
        Pause,
        Presale,
        PublicSale
    }

    bytes32 public constant MINTER_TYPEHASH =
        keccak256("Minter(address recipient,uint256 limit)");
    address private constant WALLET_A =
        0x83739A8Ec78f74Ed2f1e6256fEa391DB01F1566F;
    address private constant WALLET_B =
        0x675c2f05778554Bd02023eF0d8b163826f6696d6;
    address private constant WALLET_C =
        0x1412938f955b5f8e3c9d8551BfDE0C728Cfd7145;
    address private constant WALLET_D =
        0xAfa3E05bE3c298dC122E47864b011cD42eDa1411;

    uint256 public presalePrice = 0.18 ether;
    uint256 public publicSalePrice = 0.2 ether;
    address private amartyaContractAddress;

    uint256 public maxSupply;
    string public baseURI;
    Stage public stage;
    address public signer;

    mapping(address => uint256) public PresaleMinter;

    modifier notContract() {
        require(!_isContract(_msgSender()), "NOT_ALLOWED_CONTRACT");
        require(_msgSender() == tx.origin, "NOT_ALLOWED_PROXY");
        _;
    }
    modifier approvedCaller() {
        require(amartyaContractAddress == msg.sender, "Invalid Caller");
        _;
    }

    constructor(
        string memory _previewURI,
        address _signer,
        address _royaltyAddress,
        uint256 _maxSupply
    ) ERC721A("Amartya Gate", "GATE") EIP712("AmartyaGate", "1.0.0") {
        stage = Stage.Pause;
        signer = _signer;
        baseURI = _previewURI;
        maxSupply = _maxSupply;
        _setDefaultRoyalty(_royaltyAddress, 500);
    }

    /// @dev override tokenId to start from 1
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public payable override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /// @notice mint NFT for whitelisted user
    /// @param _signature signature to mint NFT
    function presaleMint(
        uint256 _amount,
        uint256 _limit,
        bytes calldata _signature
    ) external payable nonReentrant notContract {
        require(stage == Stage.Presale, "STAGE_NMATCH");
        require(
            PresaleMinter[msg.sender] + _amount <= _limit,
            "LIMIT_EXCEEDED"
        );
        require(
            signer == _verify(_msgSender(), _limit, _signature),
            "INVALID_SIGNATURE"
        );
        require(totalSupply() + _amount <= maxSupply, "SUPPLY_EXCEEDED");
        require(msg.value >= (presalePrice * _amount), "INSUFFICIENT_FUND");

        PresaleMinter[msg.sender] += _amount;
        _mint(msg.sender, _amount);
    }

    /// @notice Mint NFT for public user
    function publicSaleMint(
        uint256 _amount
    ) external payable nonReentrant notContract {
        require(stage == Stage.PublicSale, "STAGE_NMATCH");
        require(_amount <= 3, "LIMIT_TX");
        require(totalSupply() + _amount <= maxSupply, "SUPPLY_EXCEEDED");
        require(msg.value >= publicSalePrice * _amount, "INSUFFICIENT_FUND");

        _mint(msg.sender, _amount);
    }

    /// @notice Sent NFT Airdrop to an address
    /// @param _to list of address NFT recipient
    /// @param _amount list of total amount for the recipient
    function mintTo(
        address[] calldata _to,
        uint256[] calldata _amount
    ) external onlyOwner {
        for (uint256 i = 0; i < _to.length; i++) {
            require(
                totalSupply() + _amount[i] <= maxSupply,
                "MAX_SUPPLY_EXCEEDED"
            );
            _mint(_to[i], _amount[i]);
        }
    }

    function _verify(
        address _recipient,
        uint256 _amountLimit,
        bytes calldata _sign
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(MINTER_TYPEHASH, _recipient, _amountLimit))
        );
        return ECDSA.recover(digest, _sign);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function burn(uint256 _tokenId) external approvedCaller {
        _burn(_tokenId, false);
    }

    /// @notice Set base URI for the NFT.
    /// @param _uri base URI (can be ipfs/https)
    function setBaseURI(string calldata _uri) external onlyOwner {
        baseURI = _uri;
    }

    /// @notice Set Stage of NFT Contract.
    /// @param _stage stage of nft contract
    function setStage(Stage _stage) external onlyOwner {
        stage = _stage;
    }

    /// @notice Set signer for whitelist/redeem NFT.
    /// @param _signer address of signer
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    /// @notice Set royalties for EIP 2981.
    /// @param _recipient the recipient of royalty
    /// @param _amount the amount of royalty (use bps)
    function setRoyalties(
        address _recipient,
        uint96 _amount
    ) external onlyOwner {
        _setDefaultRoyalty(_recipient, _amount);
    }

    /// @notice Set presale mint price.
    /// @param _price new configured price.
    function setPresalePrice(uint256 _price) external onlyOwner {
        presalePrice = _price;
    }

    /// @notice Set public mint price.
    /// @param _price new configured price.
    function setPublicSalePrice(uint256 _price) external onlyOwner {
        publicSalePrice = _price;
    }

    function setAmartyaContract(address _contractAddress) external onlyOwner {
        amartyaContractAddress = _contractAddress;
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function withdrawAll() external onlyOwner {
        require(address(this).balance > 0, "BALANCE_ZERO");
        uint256 walletABalance = address(this).balance * 2625 / 10000;
        uint256 walletBBalance = address(this).balance * 3000 / 10000;
        uint256 walletCBalance = address(this).balance * 875 / 10000;
        uint256 walletDBalance = address(this).balance * 3500 / 10000;

        sendValue(payable(WALLET_A), walletABalance);
        sendValue(payable(WALLET_B), walletBBalance);
        sendValue(payable(WALLET_C), walletCBalance);
        sendValue(payable(WALLET_D), walletDBalance);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721A, ERC2981) returns (bool) {
        // IERC165: 0x01ffc9a7, IERC721: 0x80ac58cd, IERC721Metadata: 0x5b5e139f, IERC29081: 0x2a55205a
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function tokenURI(
        uint256 _id
    ) public view override returns (string memory) {
        require(_exists(_id), "Token does not exist");

        return string(abi.encodePacked(baseURI, _toString(_id)));
    }
}

