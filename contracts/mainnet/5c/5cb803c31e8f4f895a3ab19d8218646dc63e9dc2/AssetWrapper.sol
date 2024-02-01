// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ERC721Holder.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ERC1155Holder.sol";
import "./IERC1155.sol";
import "./Context.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./IAssetWrapper.sol";
import "./ERC721Permit.sol";

/**
 * @dev {ERC721} token allowing users to create bundles of assets.
 *
 * Users can create new bundles, which grants them an NFT to
 * reclaim all assets stored in the bundle. They can then
 * store various types of assets in that bundle. The bundle NFT
 * can then be used or traded as an asset in its own right.
 * At any time, the holder of the bundle NFT can redeem it for the
 * underlying assets.
 */
contract AssetWrapper is
    Context,
    ERC721Enumerable,
    ERC721Burnable,
    ERC1155Holder,
    ERC721Holder,
    ERC721Permit,
    IAssetWrapper,
    Ownable,
    ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 private _tokenIdTracker;

    struct ERC20Holding {
        address tokenAddress;
        uint256 amount;
    }
    mapping(uint256 => ERC20Holding[]) public bundleERC20Holdings;

    struct ERC721Holding {
        address tokenAddress;
        uint256 tokenId;
    }
    mapping(uint256 => ERC721Holding[]) public bundleERC721Holdings;

    struct ERC1155Holding {
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }
    mapping(uint256 => ERC1155Holding[]) public bundleERC1155Holdings;

    mapping(uint256 => uint256) public bundleETHHoldings;

    mapping(uint256 => bool) private _usedTokenIds;
    // Start at 300 to prevent collisions with previous asset wrapper
    uint256 private immutable TOKEN_ID_START;

    address public rContract;

    /**
     * @dev Initializes the token with name and symbol parameters
     */
    constructor(string memory name, string memory symbol, uint256 startNum) ERC721(name, symbol) ERC721Permit(name) {
        TOKEN_ID_START = startNum;
        _tokenIdTracker = startNum;
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function initializeBundle(address to) external override {
        require(!_usedTokenIds[_tokenIdTracker], "Already used");

        _mint(to, _tokenIdTracker);

        _usedTokenIds[_tokenIdTracker] = true;
        _tokenIdTracker += 1;
    }

    function initializeBundleWithId(address to, uint256 tokenId) external {
        require(msg.sender == rContract, "Not allowed");
        require(tokenId < TOKEN_ID_START, "Invalid tokenId");
        require(!_usedTokenIds[tokenId], "Already used");

        _usedTokenIds[tokenId] = true;
        _mint(to, tokenId);
    }

    function setRContract(address _rContract) external onlyOwner {
        rContract = _rContract;
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function depositERC20(
        address tokenAddress,
        uint256 amount,
        uint256 bundleId
    ) external override nonReentrant {
        require(_exists(bundleId), "Bundle does not exist");
        require(_isApprovedOrOwner(_msgSender(), bundleId), "AssetWrapper: Non-owner deposit");

        IERC20(tokenAddress).safeTransferFrom(_msgSender(), address(this), amount);

        // Note: there can be multiple `ERC20Holding` objects for the same token contract
        // in a given bundle. We could deduplicate them here, though I don't think
        // it's worth the extra complexity - the end effect is the same in either case.
        bundleERC20Holdings[bundleId].push(ERC20Holding(tokenAddress, amount));
        emit DepositERC20(_msgSender(), bundleId, tokenAddress, amount);
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function depositERC721(
        address tokenAddress,
        uint256 tokenId,
        uint256 bundleId
    ) external override nonReentrant {
        require(_exists(bundleId), "Bundle does not exist");
        require(_isApprovedOrOwner(_msgSender(), bundleId), "AssetWrapper: Non-owner deposit");

        IERC721(tokenAddress).safeTransferFrom(_msgSender(), address(this), tokenId);

        bundleERC721Holdings[bundleId].push(ERC721Holding(tokenAddress, tokenId));
        emit DepositERC721(_msgSender(), bundleId, tokenAddress, tokenId);
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function depositERC1155(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 bundleId
    ) external override nonReentrant {
        require(_exists(bundleId), "Bundle does not exist");
        require(_isApprovedOrOwner(_msgSender(), bundleId), "AssetWrapper: Non-owner deposit");

        IERC1155(tokenAddress).safeTransferFrom(_msgSender(), address(this), tokenId, amount, "");

        bundleERC1155Holdings[bundleId].push(ERC1155Holding(tokenAddress, tokenId, amount));
        emit DepositERC1155(_msgSender(), bundleId, tokenAddress, tokenId, amount);
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function depositETH(uint256 bundleId) external payable override {
        require(_exists(bundleId), "Bundle does not exist");

        uint256 amount = msg.value;

        bundleETHHoldings[bundleId] = bundleETHHoldings[bundleId].add(amount);
        emit DepositETH(_msgSender(), bundleId, amount);
    }

    /**
     * @inheritdoc IAssetWrapper
     */
    function withdraw(uint256 bundleId) external override nonReentrant {
        require(_isApprovedOrOwner(_msgSender(), bundleId), "AssetWrapper: Non-owner withdrawal");
        burn(bundleId);

        ERC20Holding[] memory erc20Holdings = bundleERC20Holdings[bundleId];
        for (uint256 i = 0; i < erc20Holdings.length; i++) {
            IERC20(erc20Holdings[i].tokenAddress).safeTransfer(_msgSender(), erc20Holdings[i].amount);
        }
        delete bundleERC20Holdings[bundleId];

        ERC721Holding[] memory erc721Holdings = bundleERC721Holdings[bundleId];
        for (uint256 i = 0; i < erc721Holdings.length; i++) {
            IERC721(erc721Holdings[i].tokenAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                erc721Holdings[i].tokenId
            );
        }
        delete bundleERC721Holdings[bundleId];

        ERC1155Holding[] memory erc1155Holdings = bundleERC1155Holdings[bundleId];
        for (uint256 i = 0; i < erc1155Holdings.length; i++) {
            IERC1155(erc1155Holdings[i].tokenAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                erc1155Holdings[i].tokenId,
                erc1155Holdings[i].amount,
                ""
            );
        }
        delete bundleERC1155Holdings[bundleId];

        uint256 ethHoldings = bundleETHHoldings[bundleId];
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _msgSender().call{ value: ethHoldings }("");
        require(success, "Failed to withdraw ETH");
        delete bundleETHHoldings[bundleId];

        emit Withdraw(_msgSender(), bundleId);
    }

    function tryWithdraw(uint256 bundleId) external nonReentrant {
        require(_isApprovedOrOwner(_msgSender(), bundleId), "AssetWrapper: Non-owner deposit");
        burn(bundleId);

        ERC20Holding[] memory erc20Holdings = bundleERC20Holdings[bundleId];
        for (uint256 i = 0; i < erc20Holdings.length; i++) {
            try IERC20(erc20Holdings[i].tokenAddress).transfer(
                _msgSender(),
                erc20Holdings[i].amount
            ) {} catch {}
        }
        delete bundleERC20Holdings[bundleId];

        ERC721Holding[] memory erc721Holdings = bundleERC721Holdings[bundleId];
        for (uint256 i = 0; i < erc721Holdings.length; i++) {
            try IERC721(erc721Holdings[i].tokenAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                erc721Holdings[i].tokenId
            ) {} catch {}
        }
        delete bundleERC721Holdings[bundleId];

        ERC1155Holding[] memory erc1155Holdings = bundleERC1155Holdings[bundleId];
        for (uint256 i = 0; i < erc1155Holdings.length; i++) {
            try IERC1155(erc1155Holdings[i].tokenAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                erc1155Holdings[i].tokenId,
                erc1155Holdings[i].amount,
                ""
            ) {} catch {}
        }
        delete bundleERC1155Holdings[bundleId];

        uint256 ethHoldings = bundleETHHoldings[bundleId];
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _msgSender().call{ value: ethHoldings }("");
        require(success, "Failed to withdraw ETH");
        delete bundleETHHoldings[bundleId];

        emit Withdraw(_msgSender(), bundleId);
    }

    function numERC20Holdings(uint256 bundleId) external view returns (uint256) {
        return bundleERC20Holdings[bundleId].length;
    }

    function numERC721Holdings(uint256 bundleId) external view returns (uint256) {
        return bundleERC721Holdings[bundleId].length;
    }

    function numERC1155Holdings(uint256 bundleId) external view returns (uint256) {
        return bundleERC1155Holdings[bundleId].length;
    }

    /**
     * @dev Hook that is called before any token transfer
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, ERC1155Receiver)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

