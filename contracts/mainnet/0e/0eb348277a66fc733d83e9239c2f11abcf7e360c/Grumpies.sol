// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {OperatorFilterer} from "./OperatorFilterer.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IERC2981Upgradeable, ERC2981Upgradeable} from "./ERC2981Upgradeable.sol";
import "./MerkleProofUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import {IERC721AUpgradeable, ERC721AUpgradeable} from "./ERC721AUpgradeable.sol";
import {ERC721AQueryableUpgradeable} from "./ERC721AQueryableUpgradeable.sol";
//
//
//               _  .-')                 _   .-')       _ (`-.               ('-.     .-')
//              ( \( -O )               ( '.( OO )_    ( (OO  )            _(  OO)   ( OO ).
//   ,----.      ,------.   ,--. ,--.    ,--.   ,--.) _.`     \   ,-.-')  (,------. (_)---\_)
//  '  .-./-')   |   /`. '  |  | |  |    |   `.'   | (__...--''   |  |OO)  |  .---' /    _ |
//  |  |_( O- )  |  /  | |  |  | | .-')  |         |  |  /  | |   |  |  \  |  |     \  :` `.
//  |  | .--, \  |  |_.' |  |  |_|( OO ) |  |'.'|  |  |  |_.' |   |  |(_/ (|  '--.   '..`''.)
// (|  | '. (_/  |  .  '.'  |  | | `-' / |  |   |  |  |  .___.'  ,|  |_.'  |  .--'  .-._)   \
//  |  '--'  |   |  |\  \  ('  '-'(_.-'  |  |   |  |  |  |      (_|  |     |  `---. \       /
//   `------'    `--' '--'   `-----'     `--'   `--'  `--'        `--'     `------'  `-----'
//
//
//
/// @title Grumpies
/// @author aceplxx (https://twitter.com/aceplxx)

enum SaleState {
    Paused,
    Presale,
    Public
}

contract Grumpies is
    ERC721AQueryableUpgradeable,
    OperatorFilterer,
    OwnableUpgradeable,
    ERC2981Upgradeable,
    UUPSUpgradeable
{
    SaleState public saleState;
    string public baseURI;
    address public constant VAULT = 0x096B06F5b50139Ad1Bb835f642a8C6f7b870781a;
    uint256 public constant TEAM_RESERVES = 129;
    uint256 public maxSupply;
    uint256 public presalePrice;
    uint256 public publicPrice;
    uint256 public maxPerTx;
    uint256 public maxPerWl;

    bool public operatorFilteringEnabled;

    bytes32 public presaleRoot;

    error SaleNotActive();

    function initialize(string memory name, string memory symbol)
        public
        initializerERC721A
        initializer
    {
        __ERC721A_init(name, symbol);
        __Ownable_init();
        __ERC2981_init();

        _registerForOperatorFiltering();
        operatorFilteringEnabled = true;

        //7% royalty.
        _setDefaultRoyalty(VAULT, 700);
        baseURI = "https://nft.grumpies.xyz/api/metadata/";
        presalePrice = 0.019 ether;
        publicPrice = 0.028 ether;
        maxPerTx = 5;
        maxPerWl = 2;
        maxSupply = 4000;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setPresaleRoot(bytes32 _root) external onlyOwner {
        presaleRoot = _root;
    }

    function setSaleState(SaleState state) external onlyOwner {
        saleState = state;
    }

    function cutSupply(uint256 newSupply) external onlyOwner {
        require(newSupply < maxSupply, "Only decrease allowed");
        require(newSupply >= totalSupply(), "Faulty behavior");
        maxSupply = newSupply;
    }

    function setMintConfig(
        uint256 wl_,
        uint256 public_,
        uint256 maxPerTx_,
        uint256 maxPerWl_
    ) external onlyOwner {
        presalePrice = wl_;
        publicPrice = public_;
        maxPerTx = maxPerTx_;
        maxPerWl = maxPerWl_;
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function withdraw() external onlyOwner {
        bool success;
        (success, ) = payable(VAULT).call{value: address(this).balance}("");
        require(success, "failed");
    }

    function _isWhitelisted(bytes32[] calldata _merkleProof, address _address)
        internal
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(_address));
        bool whitelisted = MerkleProofUpgradeable.verify(
            _merkleProof,
            presaleRoot,
            leaf
        );

        return whitelisted;
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI()
        internal
        view
        virtual
        override(ERC721AUpgradeable)
        returns (string memory)
    {
        return baseURI;
    }

    function presaleMint(bytes32[] calldata _merkleProof, uint256 quantity)
        external
        payable
    {
        require(
            totalSupply() + quantity <= maxSupply,
            "G: Insufficient supply"
        );
        require(
            _numberMinted(_msgSender()) + quantity <= maxPerWl,
            "G: Too much"
        );

        bool eligible = true;
        if (saleState == SaleState.Presale) {
            eligible = _isWhitelisted(_merkleProof, _msgSender());
        } else {
            revert SaleNotActive();
        }
        require(eligible, "G: Cannot mint");
        require(msg.value >= presalePrice * quantity, "G: Price incorrect");

        _mint(_msgSender(), quantity);
    }

    function publicMint(uint256 quantity) external payable {
        require(saleState == SaleState.Public, "G: Public inactive");
        require(quantity <= maxPerTx, "G: Too much");
        require(
            totalSupply() + quantity <= maxSupply,
            "G: Insufficient supply"
        );
        require(msg.value >= publicPrice * quantity, "G: Price incorrect");

        _mint(_msgSender(), quantity);
    }

    function numberMinted(address user) external view returns (uint256) {
        return _numberMinted(user);
    }

    //ERC721A function overrides for operator filtering to enable OpenSea creator royalities.

    function setApprovalForAll(address operator, bool approved)
        public
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        payable
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        payable
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        payable
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    )
        public
        payable
        override(IERC721AUpgradeable, ERC721AUpgradeable)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC721AUpgradeable, ERC721AUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            ERC2981Upgradeable.supportsInterface(interfaceId);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        public
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    function _isPriorityOperator(address operator)
        internal
        pure
        override
        returns (bool)
    {
        // OpenSea Seaport Conduit:
        // https://etherscan.io/address/0x1E0049783F008A0085193E00003D00cd54003c71
        // https://goerli.etherscan.io/address/0x1E0049783F008A0085193E00003D00cd54003c71
        return operator == address(0x1E0049783F008A0085193E00003D00cd54003c71);
    }
}

