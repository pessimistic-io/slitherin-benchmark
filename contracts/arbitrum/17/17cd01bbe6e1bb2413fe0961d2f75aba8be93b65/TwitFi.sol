// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./ERC2981.sol";
import "./DefaultOperatorFilterer.sol";
import "./Counters.sol";
import "./Pausable.sol";

contract TwitFi is DefaultOperatorFilterer, Pausable, ERC721Enumerable, Ownable, ERC2981, AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

	bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');

	string private baseURI;
    string private _contractURI;

	event Mint(uint256 tokenId, address _receiver, uint256 _twitfiId, string _type);
	event Burn(uint256 tokenId);
	event TokenTransfer(uint256 tokenId, address oldOwner, address newOwner);

    constructor(string memory _name, string memory _symbol, string memory __baseURI) ERC721(_name, _symbol) {
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        baseURI = __baseURI;
        _contractURI = __baseURI;
        _setDefaultRoyalty(msg.sender, 500);
    }

	function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner  {
        baseURI = newBaseURI;
    }

    function setContractURI(string memory _contractUri) public onlyOwner {
        _contractURI = _contractUri;
    }

    function setApprovalForAll(address operator, bool approved) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

	function _transfer(address from, address to, uint256 tokenId) internal virtual override whenNotPaused {
        super._transfer(from, to, tokenId);

        emit TokenTransfer(tokenId, from, to);
    }

	function mint(address _receiver, string memory _type, uint256 _twitfi_id) external onlyMinter whenNotPaused {
        _mintToken(_receiver, _type, _twitfi_id);
    }

	function bulkMint(address[] memory _tos, string[] memory _types, uint256[] memory _twitfi_ids) external onlyMinter whenNotPaused {
        for (uint256 i = 0; i < _tos.length; i++) {
            _mintToken(_tos[i], _types[i], _twitfi_ids[i]);
        }
    }

	function _mintToken(address _receiver, string memory _type, uint256 _twitfi_id) internal {
        _tokenIds.increment();

        uint256 _tokenId = _tokenIds.current();
        _safeMint(_receiver, _tokenId);

        emit Mint(_tokenId, _receiver, _twitfi_id, _type);
    }

	function burn(uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "burn caller is not owner nor approved");
        _burn(tokenId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

	function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function withdraw() public onlyOwner {
        uint amount = address(this).balance;
        require(amount > 0, "Insufficient balance");
        (bool success, ) = payable(owner()).call {
            value: amount
        }("");

        require(success, "Failed to send Matic");
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Minter: permission denied");
        _;
    }

    receive() payable external {}
}

