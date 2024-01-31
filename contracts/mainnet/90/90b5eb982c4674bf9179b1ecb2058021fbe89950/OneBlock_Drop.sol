// SPDX-License-Identifier: MIT

//  ██╗██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
// ███║██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
// ╚██║██████╔╝██║     ██║   ██║██║     █████╔╝
//  ██║██╔══██╗██║     ██║   ██║██║     ██╔═██╗
//  ██║██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
//  ╚═╝╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
//
//         ██████╗ ██████╗  ██████╗ ██████╗
//         ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
//         ██║  ██║██████╔╝██║   ██║██████╔╝
//         ██║  ██║██╔══██╗██║   ██║██╔═══╝
//         ██████╔╝██║  ██║╚██████╔╝██║
//         ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝

pragma solidity ^0.8.13;

import "./ERC1155Burnable.sol";
import "./Ownable.sol";
import "./ERC2981.sol";
import "./ReentrancyGuard.sol";
import {UpdatableOperatorFilterer} from "./UpdatableOperatorFilterer.sol";
import {RevokableDefaultOperatorFilterer} from "./RevokableDefaultOperatorFilterer.sol";
import "./MintContractInterface.sol";

/**
 * @dev Implementation of the tokens which are ERC1155 tokens.
 */
contract OneBlock_Drop is
    ERC1155,
    ERC1155Burnable,
    ReentrancyGuard,
    RevokableDefaultOperatorFilterer,
    Ownable,
    ERC2981
{
    /**
     * @dev The contract address for burnToMint2
     */
    address public mintContractAddress;

    /**
     * @dev The name of token.
     */
    string public name = "1B DROP";

    /**
     * @dev The name of token symbol.
     */
    string public symbol = "1B DROP";

    /**
     * @dev The token id for burning
     */
    uint256 public burnTokenId1 = 1;

    /**
     * @dev The token id for burning
     */
    uint256 public burnTokenId2 = 2;

    /**
     * @dev The price for burn minting
     */
    uint256 public burnMintPrice1 = 0.39 ether;

    /**
     * @dev The price for burn minting
     */
    uint256 public burnMintPrice2 = 0;

    /**
     * @dev The owner can toggle the 'isBurnToMintActive1' state.
     */
    bool public isBurnToMintActive1;

    /**
     * @dev The owner can toggle the 'isBurnToMintActive2' state.
     */
    bool public isBurnToMintActive2;

    /**
     * @dev The token URI per token id.
     */
    mapping(uint256 => string) private _tokenURIs;

    /**
     * @dev The burned amount by address.
     */
    mapping(address => mapping(uint256 => uint256))
        public burnedAmountByAddress;

    /**
     * @dev Constractor of this contract. Setting the royalty info.
     */
    constructor() ERC1155("") {
        setRoyaltyInfo(_msgSender(), 750); // 750 == 7.5%
    }

    modifier burnToMintCompliance(
        uint256 _mintAmount,
        uint256 _mintPrice,
        uint256 _burnTokenId,
        bool _isActive
    ) {
        require(_isActive, "burnToMint is not active yet");
        require(_mintAmount > 0, "Must mint at least 1");
        require(
            msg.value == _mintPrice * _mintAmount,
            "The mint price does not match"
        );
        address caller = _msgSender();
        require(
            balanceOf(caller, _burnTokenId) >= _mintAmount,
            "Doesn't own the enough tokens"
        );
        require(caller == tx.origin, "Cannot be called by contract");
        _;
    }

    /**
     * @dev For receiving ETH just in case someone tries to send it.
     */
    receive() external payable {}

    /**
     * @dev Airdrop the number of tokens to '_receivers'.
     * @param _receivers Addresses of the receivers.
     * @param _mintAmounts Numbers of the mints.
     * @param _tokenId Airdrop's token id.
     */
    function airdrop(
        address[] calldata _receivers,
        uint256[] calldata _mintAmounts,
        uint256 _tokenId
    ) external onlyOwner {
        uint256 receiverAmount = _receivers.length;

        require(
            receiverAmount == _mintAmounts.length,
            "The amount doesn't match."
        );
        for (uint256 i = 0; i < receiverAmount; ) {
            _mint(_receivers[i], _tokenId, _mintAmounts[i], "");
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Burn own NFTs and mint new ERC1155 tokens.
     * @param _amount Numbers of burning own NFTs and minting new ones.
     */
    function burnToMint1(uint256 _amount)
        external
        payable
        nonReentrant
        burnToMintCompliance(
            _amount,
            burnMintPrice1,
            burnTokenId1,
            isBurnToMintActive1
        )
    {
        address caller = _msgSender();
        unchecked {
            burnedAmountByAddress[caller][burnTokenId1] += _amount;
        }
        burn(caller, burnTokenId1, _amount);
        _mint(caller, burnTokenId2, _amount, "");
    }

    /**
     * @dev Burn own NFTs and mint new tokens. Call this function after calling 'setMintContract'.
     * @param _amount Numbers of burning own NFTs and minting new ones.
     */
    function burnToMint2(uint256 _amount)
        external
        payable
        nonReentrant
        burnToMintCompliance(
            _amount,
            burnMintPrice2,
            burnTokenId2,
            isBurnToMintActive2
        )
    {
        address caller = _msgSender();
        unchecked {
            burnedAmountByAddress[caller][burnTokenId2] += _amount;
        }
        burn(caller, burnTokenId2, _amount);

        MintContractInterface mintContracts = MintContractInterface(
            mintContractAddress
        );
        mintContracts.mintAfterBurning(caller, _amount);
    }

    /**
     * @dev Specify the token id and set the new token URI to '_tokenURIs'.
     */
    function setURI(uint256 _tokenId, string memory _newTokenURI)
        external
        onlyOwner
    {
        _tokenURIs[_tokenId] = _newTokenURI;
    }

    /**
     * @dev Set the burn token id1
     */
    function setBurnTokenId1(uint256 _tokenId) external onlyOwner {
        burnTokenId1 = _tokenId;
    }

    /**
     * @dev Set the burn token id2
     */
    function setBurnTokenId2(uint256 _tokenId) external onlyOwner {
        burnTokenId2 = _tokenId;
    }

    /**
     * @dev Set the burn mint price1
     */
    function setBurnMintPrice1(uint256 _price) external onlyOwner {
        burnMintPrice1 = _price;
    }

    /**
     * @dev Set the burn mint price2
     */
    function setBurnMintPrice2(uint256 _price) external onlyOwner {
        burnMintPrice2 = _price;
    }

    /**
     * @dev Set the mintContractAddress
     */
    function setMintContractAddress(address _address) external onlyOwner {
        mintContractAddress = _address;
    }

    /**
     * @dev Toggle the 'isBurnToMintActive1'.
     */
    function toggleBurnToMintActive1() external onlyOwner {
        isBurnToMintActive1 = !isBurnToMintActive1;
    }

    /**
     * @dev Toggle the 'isBurnToMintActive2'.
     */
    function toggleBurnToMintActive2() external onlyOwner {
        isBurnToMintActive2 = !isBurnToMintActive2;
    }

    /**
     * @notice Only the owner can withdraw all of the contract balance.
     * @dev All the balance transfers to the owner's address.
     */
    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        require(success, "withdraw is failed!!");
    }

    /**
     * @dev Set the new royalty fee and the new receiver.
     */
    function setRoyaltyInfo(address _receiver, uint96 _royaltyFee)
        public
        onlyOwner
    {
        _setDefaultRoyalty(_receiver, _royaltyFee);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return
            ERC1155.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    /**
     * @dev Return tokenURI for the specified token ID.
     * @param _tokenId The token ID the token URI is returned for.
     */
    function uri(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        return _tokenURIs[_tokenId];
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function owner()
        public
        view
        virtual
        override(Ownable, UpdatableOperatorFilterer)
        returns (address)
    {
        return Ownable.owner();
    }
}

